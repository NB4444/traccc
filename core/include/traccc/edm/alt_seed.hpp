/** TRACCC library, part of the ACTS project (R&D line)
 *
 * (c) 2022 CERN for the benefit of the ACTS project
 *
 * Mozilla Public License Version 2.0
 */

#pragma once

#include "traccc/edm/container.hpp"
#include "traccc/edm/spacepoint.hpp"

namespace traccc {

/// Seed consisting of three spacepoints, z origin and weight
/// This differs from (non-alt) seed in the link_type definition
struct alt_seed {

    using link_type = spacepoint_collection_types::host::size_type;

    link_type spB_link;
    link_type spM_link;
    link_type spT_link;

    scalar weight;
    scalar z_vertex;

    TRACCC_HOST_DEVICE
    std::array<measurement, 3> get_measurements(
        const spacepoint_collection_types::const_view& spacepoints_view) const {
        const spacepoint_collection_types::const_device spacepoints(
            spacepoints_view);
        return {spacepoints.at(spB_link).meas, spacepoints.at(spM_link).meas,
                spacepoints.at(spT_link).meas};
    }

    TRACCC_HOST_DEVICE
    std::array<spacepoint, 3> get_spacepoints(
        const spacepoint_collection_types::const_view& spacepoints_view) const {
        const spacepoint_collection_types::const_device spacepoints(
            spacepoints_view);
        return {spacepoints.at(spB_link), spacepoints.at(spM_link),
                spacepoints.at(spT_link)};
    }
};

/// Declare all seed collection types
using alt_seed_collection_types = collection_types<alt_seed>;

}  // namespace traccc
