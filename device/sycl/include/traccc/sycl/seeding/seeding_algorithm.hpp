/** TRACCC library, part of the ACTS project (R&D line)
 *
 * (c) 2021-2022 CERN for the benefit of the ACTS project
 *
 * Mozilla Public License Version 2.0
 */

#pragma once

// Library include(s).
#include "traccc/sycl/seeding/seed_finding.hpp"
#include "traccc/sycl/seeding/spacepoint_binning.hpp"
#include "traccc/sycl/utils/queue_wrapper.hpp"

// Project include(s).
#include "traccc/edm/alt_seed.hpp"
#include "traccc/edm/spacepoint.hpp"
#include "traccc/utils/algorithm.hpp"

// VecMem include(s).
#include <vecmem/containers/data/vector_buffer.hpp>

// traccc library include(s).
#include "traccc/utils/memory_resource.hpp"

namespace traccc::sycl {

/// Main algorithm for performing the track seeding using oneAPI/SYCL
class seeding_algorithm : public algorithm<alt_seed_collection_types::buffer(
                              const spacepoint_collection_types::const_view&)> {

    public:
    /// Constructor for the seed finding algorithm
    ///
    /// @param mr is a struct of memory resources (shared or host & device)
    /// @param queue The SYCL queue to work with
    ///
    seeding_algorithm(const traccc::memory_resource& mr,
                      const queue_wrapper& queue);

    /// Operator executing the algorithm.
    ///
    /// @param spacepoints_view is a view of all spacepoints in the event
    /// @return the buffer of track seeds reconstructed from the spacepoints
    ///
    output_type operator()(const spacepoint_collection_types::const_view&
                               spacepoints_view) const override;

    private:
    /// Sub-algorithm performing the spacepoint binning
    spacepoint_binning m_spacepoint_binning;
    /// Sub-algorithm performing the seed finding
    seed_finding m_seed_finding;

};  // class seeding_algorithm

}  // namespace traccc::sycl
