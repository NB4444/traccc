# TRACCC library, part of the ACTS project (R&D line)
#
# (c) 2021-2022 CERN for the benefit of the ACTS project
#
# Mozilla Public License Version 2.0

# Project include(s).
include( traccc-compiler-options-cuda )

# External(s).
find_package( CUDAToolkit REQUIRED )

SET(DLIDWID "-DLIKWID_PERFMON")

traccc_add_executable( seq_example_cuda "seq_example_cuda.cpp"
   LINK_LIBRARIES vecmem::core vecmem::cuda traccc::io traccc::performance
                  traccc::core traccc::device_common traccc::cuda
                  traccc::options )
traccc_add_executable( seeding_example_cuda "seeding_example_cuda.cpp"
   LINK_LIBRARIES vecmem::core vecmem::cuda traccc::io traccc::performance
                  traccc::core traccc::device_common traccc::cuda
                  traccc::options )

# Add likwid
find_package(likwid REQUIRED)
add_definitions(${DLIDWID})

#
# Set up the "throughput applications".
#
add_library( traccc_examples_cuda STATIC
   "full_chain_algorithm.hpp"
   "full_chain_algorithm.cpp" )

target_include_directories(traccc_examples_cuda PUBLIC /opt/ohpc/pub/libs/gnu9/likwid/5.0.1/include)

target_link_libraries( traccc_examples_cuda
   PUBLIC CUDA::cudart vecmem::core vecmem::cuda traccc::core
          traccc::device_common traccc::cuda ${LIKWID_LIBRARIES})

traccc_add_executable( throughput_st_cuda "throughput_st.cpp"
   LINK_LIBRARIES vecmem::core vecmem::cuda traccc::io traccc::performance
                  traccc::core traccc::device_common traccc::cuda
                  traccc::options traccc_examples_cuda )

traccc_add_executable( throughput_mt_cuda "throughput_mt.cpp"
   LINK_LIBRARIES TBB::tbb vecmem::core vecmem::cuda traccc::io traccc::performance
                  traccc::core traccc::device_common traccc::cuda
                  traccc::options traccc_examples_cuda )
