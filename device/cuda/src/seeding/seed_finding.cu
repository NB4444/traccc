/** TRACCC library, part of the ACTS project (R&D line)
 *
 * (c) 2021-2023 CERN for the benefit of the ACTS project
 *
 * Mozilla Public License Version 2.0
 */

// Local include(s).
#include "../utils/utils.hpp"
#include "traccc/cuda/seeding/seed_finding.hpp"
#include "traccc/cuda/utils/definitions.hpp"

// Project include(s).
#include "traccc/cuda/utils/make_prefix_sum_buff.hpp"
#include "traccc/device/fill_prefix_sum.hpp"
#include "traccc/device/make_prefix_sum_buffer.hpp"
#include "traccc/edm/device/device_doublet.hpp"
#include "traccc/edm/device/device_triplet.hpp"
#include "traccc/edm/device/doublet_counter.hpp"
#include "traccc/edm/device/seeding_global_counter.hpp"
#include "traccc/edm/device/triplet_counter.hpp"
#include "traccc/seeding/device/count_doublets.hpp"
#include "traccc/seeding/device/count_triplets.hpp"
#include "traccc/seeding/device/find_doublets.hpp"
#include "traccc/seeding/device/find_triplets.hpp"
#include "traccc/seeding/device/reduce_triplet_counts.hpp"
#include "traccc/seeding/device/select_seeds.hpp"
#include "traccc/seeding/device/update_triplet_weights.hpp"

// VecMem include(s).
#include "vecmem/utils/cuda/copy.hpp"

// System include(s).
#include <algorithm>
#include <random>
#include <vector>


std::vector<int> generateRandomNumberList(int n) {
    std::random_device rd;
    std::vector<int> numbers;
    std::mt19937 rng(rd());
    for (int i = 0; i < n; ++i) {
        numbers.push_back(i);
    }
    std::shuffle(numbers.begin(), numbers.end(), rng);
    return numbers;
}

namespace traccc::cuda {
namespace kernels {

/// CUDA kernel for running @c traccc::device::count_doublets
__global__ void count_doublets(
    seedfinder_config config, sp_grid_const_view sp_grid,
    vecmem::data::vector_view<const device::prefix_sum_element_t> sp_prefix_sum,
    device::doublet_counter_collection_types::view doublet_counter,
    unsigned int& nMidBot, unsigned int& nMidTop,
    int* rng_vector) {

    device::count_doublets(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)], config,
                           sp_grid, sp_prefix_sum, doublet_counter, nMidBot,
                           nMidTop);
}

/// CUDA kernel for running @c traccc::device::find_doublets
__global__ void find_doublets(
    seedfinder_config config, sp_grid_const_view sp_grid,
    device::doublet_counter_collection_types::const_view doublet_counter,
    device::device_doublet_collection_types::view mb_doublets,
    device::device_doublet_collection_types::view mt_doublets,
    int* rng_vector) {

    device::find_doublets(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)], config,
                          sp_grid, doublet_counter, mb_doublets, mt_doublets);
}

/// CUDA kernel for running @c traccc::device::count_triplets
__global__ void count_triplets(
    seedfinder_config config, sp_grid_const_view sp_grid,
    device::doublet_counter_collection_types::const_view doublet_counter,
    device::device_doublet_collection_types::const_view mb_doublets,
    device::device_doublet_collection_types::const_view mt_doublets,
    device::triplet_counter_spM_collection_types::view spM_counter,
    device::triplet_counter_collection_types::view midBot_counter,
    int* rng_vector) {

    device::count_triplets(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)], config,
                           sp_grid, doublet_counter, mb_doublets, mt_doublets,
                           spM_counter, midBot_counter);
}

/// CUDA kernel for running @c traccc::device::reduce_triplet_counts
__global__ void reduce_triplet_counts(
    device::doublet_counter_collection_types::const_view doublet_counter,
    device::triplet_counter_spM_collection_types::view spM_counter,
    unsigned int& num_triplets,
    int* rng_vector) {

    device::reduce_triplet_counts(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)],
                                  doublet_counter, spM_counter, num_triplets);
}

/// CUDA kernel for running @c traccc::device::find_triplets
__global__ void find_triplets(
    seedfinder_config config, seedfilter_config filter_config,
    sp_grid_const_view sp_grid,
    device::doublet_counter_collection_types::const_view doublet_counter,
    device::device_doublet_collection_types::const_view mt_doublets,
    device::triplet_counter_spM_collection_types::const_view spM_tc,
    device::triplet_counter_collection_types::const_view midBot_tc,
    device::device_triplet_collection_types::view triplet_view,
    int* rng_vector) {

    device::find_triplets(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)], config,
                          filter_config, sp_grid, doublet_counter, mt_doublets,
                          spM_tc, midBot_tc, triplet_view);
}

/// CUDA kernel for running @c traccc::device::update_triplet_weights
__global__ void update_triplet_weights(
    seedfilter_config filter_config, sp_grid_const_view sp_grid,
    device::triplet_counter_spM_collection_types::const_view spM_tc,
    device::triplet_counter_collection_types::const_view midBot_tc,
    device::device_triplet_collection_types::view triplet_view,
    int* rng_vector) {

    // Array for temporary storage of quality parameters for comparing triplets
    // within weight updating kernel
    extern __shared__ scalar data[];
    // Each thread uses compatSeedLimit elements of the array
    scalar* dataPos = &data[threadIdx.x * filter_config.compatSeedLimit];

    device::update_triplet_weights(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)],
                                   filter_config, sp_grid, spM_tc, midBot_tc,
                                   dataPos, triplet_view);
}

/// CUDA kernel for running @c traccc::device::select_seeds
__global__ void select_seeds(
    seedfilter_config filter_config,
    spacepoint_collection_types::const_view spacepoints_view,
    sp_grid_const_view internal_sp_view,
    device::triplet_counter_spM_collection_types::const_view spM_tc,
    device::triplet_counter_collection_types::const_view midBot_tc,
    device::device_triplet_collection_types::view triplet_view,
    alt_seed_collection_types::view seed_view,
    int* rng_vector) {

    // Array for temporary storage of triplets for comparing within seed
    // selecting kernel
    extern __shared__ triplet data2[];
    // Each thread uses max_triplets_per_spM elements of the array
    triplet* dataPos = &data2[threadIdx.x * filter_config.max_triplets_per_spM];

    device::select_seeds(rng_vector[(threadIdx.x + blockIdx.x * blockDim.x)], filter_config,
                         spacepoints_view, internal_sp_view, spM_tc, midBot_tc,
                         triplet_view, dataPos, seed_view);
}

}  // namespace kernels

seed_finding::seed_finding(const seedfinder_config& config,
                           const seedfilter_config& filter_config,
                           const traccc::memory_resource& mr,
                           vecmem::copy& copy, stream& str)
    : m_seedfinder_config(config.toInternalUnits()),
      m_seedfilter_config(filter_config.toInternalUnits()),
      m_mr(mr),
      m_copy(copy),
      m_stream(str) {}

seed_finding::output_type seed_finding::operator()(
    const spacepoint_collection_types::const_view& spacepoints_view,
    const sp_grid_const_view& g2_view) const {

    // Get a convenience variable for the stream that we'll be using.
    cudaStream_t stream = details::get_stream(m_stream);

    // Get the sizes from the grid view
    auto grid_sizes = m_copy.get_sizes(g2_view._data_view);

    // Create prefix sum buffer
    vecmem::data::vector_buffer sp_grid_prefix_sum_buff =
        make_prefix_sum_buff(grid_sizes, m_copy, m_mr, m_stream);

    // Set up the doublet counter buffer.
    device::doublet_counter_collection_types::buffer doublet_counter_buffer = {
        m_copy.get_size(sp_grid_prefix_sum_buff), 0, m_mr.main};
    m_copy.setup(doublet_counter_buffer);

    // Calculate the number of threads and thread blocks to run the doublet
    // counting kernel for.
    const unsigned int nDoubletCountThreads = WARP_SIZE * 2;
    const unsigned int nDoubletCountBlocks =
        (m_copy.get_size(sp_grid_prefix_sum_buff) + nDoubletCountThreads - 1) /
        nDoubletCountThreads;

    const unsigned int nThreads_d_count = nDoubletCountThreads * nDoubletCountBlocks;

    std::vector<int> h_vec_count_double = generateRandomNumberList(nThreads_d_count);
    int* d_vec_count_double;
    cudaMalloc((void**)&d_vec_count_double, nThreads_d_count * sizeof(int));
    cudaMemcpy(d_vec_count_double, h_vec_count_double.data(), nThreads_d_count * sizeof(int), cudaMemcpyHostToDevice);

    // Counter for the total number of doublets and triplets
    vecmem::unique_alloc_ptr<device::seeding_global_counter>
        globalCounter_device =
            vecmem::make_unique_alloc<device::seeding_global_counter>(
                m_mr.main);
    CUDA_ERROR_CHECK(cudaMemsetAsync(globalCounter_device.get(), 0,
                                     sizeof(device::seeding_global_counter),
                                     stream));

    // Count the number of doublets that we need to produce.
    kernels::count_doublets<<<nDoubletCountBlocks, nDoubletCountThreads, 0,
                              stream>>>(
        m_seedfinder_config, g2_view, sp_grid_prefix_sum_buff,
        doublet_counter_buffer, (*globalCounter_device).m_nMidBot,
        (*globalCounter_device).m_nMidTop, d_vec_count_double);

    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec_count_double);

    // Get the summary values.
    device::seeding_global_counter globalCounter_host;
    CUDA_ERROR_CHECK(cudaMemcpyAsync(&globalCounter_host,
                                     globalCounter_device.get(),
                                     sizeof(device::seeding_global_counter),
                                     cudaMemcpyDeviceToHost, stream));
    m_stream.synchronize();

    // Set up the doublet counter buffers.
    device::device_doublet_collection_types::buffer doublet_buffer_mb = {
        globalCounter_host.m_nMidBot, m_mr.main};
    m_copy.setup(doublet_buffer_mb);
    device::device_doublet_collection_types::buffer doublet_buffer_mt = {
        globalCounter_host.m_nMidTop, m_mr.main};
    m_copy.setup(doublet_buffer_mt);

    // Calculate the number of threads and thread blocks to run the doublet
    // finding kernel for.
    const unsigned int nDoubletFindThreads = WARP_SIZE * 2;
    const unsigned int doublet_counter_buffer_size =
        m_copy.get_size(doublet_counter_buffer);
    const unsigned int nDoubletFindBlocks =
        (doublet_counter_buffer_size + nDoubletFindThreads - 1) /
        nDoubletFindThreads;

    const unsigned int nThreads_d_find = nDoubletFindThreads * nDoubletFindBlocks;

    std::vector<int> h_vec_find_double = generateRandomNumberList(nThreads_d_find);
    int* d_vec_find_double;
    cudaMalloc((void**)&d_vec_find_double, nThreads_d_find * sizeof(int));
    cudaMemcpy(d_vec_find_double, h_vec_find_double.data(), nThreads_d_find * sizeof(int), cudaMemcpyHostToDevice);

    // Find all of the spacepoint doublets.
    kernels::
        find_doublets<<<nDoubletFindBlocks, nDoubletFindThreads, 0, stream>>>(
            m_seedfinder_config, g2_view, doublet_counter_buffer,
            doublet_buffer_mb, doublet_buffer_mt, d_vec_find_double);

    // Set up the triplet counter buffers
    device::triplet_counter_spM_collection_types::buffer
        triplet_counter_spM_buffer = {doublet_counter_buffer_size, m_mr.main};
    m_copy.setup(triplet_counter_spM_buffer);
    m_copy.memset(triplet_counter_spM_buffer, 0);
    device::triplet_counter_collection_types::buffer
        triplet_counter_midBot_buffer = {globalCounter_host.m_nMidBot, 0,
                                         m_mr.main};
    m_copy.setup(triplet_counter_midBot_buffer);

    // Calculate the number of threads and thread blocks to run the doublet
    // counting kernel for.
    const unsigned int nTripletCountThreads = WARP_SIZE * 2;
    const unsigned int nTripletCountBlocks =
        (globalCounter_host.m_nMidBot + nTripletCountThreads - 1) /
        nTripletCountThreads;
    const unsigned int nThreads = nTripletCountThreads * nTripletCountBlocks;

    std::vector<int> h_vec_count_triplets = generateRandomNumberList(nThreads);
    int* d_vec_count_triplets;
    cudaMalloc((void**)&d_vec_count_triplets, nThreads * sizeof(int));
    cudaMemcpy(d_vec_count_triplets, h_vec_count_triplets.data(), nThreads * sizeof(int), cudaMemcpyHostToDevice);

    // Wait here for the find doublets kernel to finish
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec_find_double);

    // Count the number of triplets that we need to produce.
    kernels::count_triplets<<<nTripletCountBlocks, nTripletCountThreads, 0,
                              stream>>>(
        m_seedfinder_config, g2_view, doublet_counter_buffer, doublet_buffer_mb,
        doublet_buffer_mt, triplet_counter_spM_buffer,
        triplet_counter_midBot_buffer, d_vec_count_triplets);

    // Calculate the number of threads and thread blocks to run the triplet
    // count reduction kernel for.
    const unsigned int nTcReductionThreads = WARP_SIZE * 2;
    const unsigned int nTcReductionBlocks =
        (doublet_counter_buffer_size + nTcReductionThreads - 1) /
        nTcReductionThreads;

    const unsigned int nThreads_t_reduce = nTcReductionThreads * nTcReductionBlocks;

    std::vector<int> h_vec_reduce_triple = generateRandomNumberList(nThreads_t_reduce);
    int* d_vec_reduce_triple;
    cudaMalloc((void**)&d_vec_reduce_triple, nThreads_t_reduce * sizeof(int));
    cudaMemcpy(d_vec_reduce_triple, h_vec_reduce_triple.data(), nThreads_t_reduce * sizeof(int), cudaMemcpyHostToDevice);

    // Wait here for the count triplets kernel to finish
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec_count_triplets);

    // Reduce the triplet counts per spM.
    kernels::reduce_triplet_counts<<<nTcReductionBlocks, nTcReductionThreads, 0,
                                     stream>>>(
        doublet_counter_buffer, triplet_counter_spM_buffer,
        (*globalCounter_device).m_nTriplets, d_vec_reduce_triple);
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();

    CUDA_ERROR_CHECK(cudaMemcpyAsync(&globalCounter_host,
                                     globalCounter_device.get(),
                                     sizeof(device::seeding_global_counter),
                                     cudaMemcpyDeviceToHost, stream));
    m_stream.synchronize();

    // Set up the triplet buffer.
    device::device_triplet_collection_types::buffer triplet_buffer = {
        globalCounter_host.m_nTriplets, m_mr.main};
    m_copy.setup(triplet_buffer);

    // Calculate the number of threads and thread blocks to run the triplet
    // finding kernel for.
    const unsigned int nTripletFindThreads = WARP_SIZE * 2;
    const unsigned int nTripletFindBlocks =
        (m_copy.get_size(triplet_counter_midBot_buffer) + nTripletFindThreads -
         1) /
        nTripletFindThreads;

    const unsigned int nThreadsFind = nTripletFindThreads * nTripletFindBlocks;

    std::vector<int> h_vec = generateRandomNumberList(nThreadsFind);
    int* d_vec;
    cudaMalloc((void**)&d_vec, nThreadsFind * sizeof(int));
    cudaMemcpy(d_vec, h_vec.data(), nThreadsFind * sizeof(int), cudaMemcpyHostToDevice);
    // Find all of the spacepoint triplets.
    kernels::
        find_triplets<<<nTripletFindBlocks, nTripletFindThreads, 0, stream>>>(
            m_seedfinder_config, m_seedfilter_config, g2_view,
            doublet_counter_buffer, doublet_buffer_mt,
            triplet_counter_spM_buffer, triplet_counter_midBot_buffer,
            triplet_buffer, d_vec);

    // Calculate the number of threads and thread blocks to run the weight
    // updating kernel for.
    const unsigned int nWeightUpdatingThreads = WARP_SIZE * 2;
    const unsigned int nWeightUpdatingBlocks =
        (globalCounter_host.m_nTriplets + nWeightUpdatingThreads - 1) /
        nWeightUpdatingThreads;

    const unsigned int nThreads_t_update = nWeightUpdatingThreads * nWeightUpdatingBlocks;

    std::vector<int> h_vec_update_triple = generateRandomNumberList(nThreads_t_update);
    int* d_vec_update_triple;
    cudaMalloc((void**)&d_vec_update_triple, nThreads_t_update * sizeof(int));
    cudaMemcpy(d_vec_update_triple, h_vec_update_triple.data(), nThreads_t_update * sizeof(int), cudaMemcpyHostToDevice);

    // Wait here for the find triplets kernel to finish
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec);

    // Update the weights of all spacepoint triplets.
    kernels::update_triplet_weights<<<
        nWeightUpdatingBlocks, nWeightUpdatingThreads,
        sizeof(scalar) * m_seedfilter_config.compatSeedLimit *
            nWeightUpdatingThreads,
        stream>>>(m_seedfilter_config, g2_view, triplet_counter_spM_buffer,
                  triplet_counter_midBot_buffer, triplet_buffer, d_vec_update_triple);

    // Create result object: collection of seeds
    alt_seed_collection_types::buffer seed_buffer(
        globalCounter_host.m_nTriplets, 0, m_mr.main);
    m_copy.setup(seed_buffer);

    // Calculate the number of threads and thread blocks to run the seed
    // selecting kernel for.
    const unsigned int nSeedSelectingThreads = WARP_SIZE * 2;
    const unsigned int nSeedSelectingBlocks =
        (doublet_counter_buffer_size + nSeedSelectingThreads - 1) /
        nSeedSelectingThreads;

    const unsigned int nThreads_seeds = nWeightUpdatingThreads * nWeightUpdatingBlocks;

    std::vector<int> h_vec_seeds = generateRandomNumberList(nThreads_seeds);
    int* d_vec_seeds;
    cudaMalloc((void**)&d_vec_seeds, nThreads_seeds * sizeof(int));
    cudaMemcpy(d_vec_seeds, h_vec_seeds.data(), nThreads_seeds * sizeof(int), cudaMemcpyHostToDevice);

    // Wait here for the update triplet weights kernel to finish
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec_update_triple);

    // Create seeds out of selected triplets
    kernels::select_seeds<<<nSeedSelectingBlocks, nSeedSelectingThreads,
                            sizeof(triplet) *
                                m_seedfilter_config.max_triplets_per_spM *
                                nSeedSelectingThreads,
                            stream>>>(m_seedfilter_config, spacepoints_view,
                                      g2_view, triplet_counter_spM_buffer,
                                      triplet_counter_midBot_buffer,
                                      triplet_buffer, seed_buffer, d_vec_seeds);
    CUDA_ERROR_CHECK(cudaGetLastError());
    m_stream.synchronize();
    cudaFree(d_vec_seeds);

    return seed_buffer;
}

}  // namespace traccc::cuda
