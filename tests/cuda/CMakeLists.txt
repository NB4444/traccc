# TRACCC library, part of the ACTS project (R&D line)
#
# (c) 2021-2023 CERN for the benefit of the ACTS project
#
# Mozilla Public License Version 2.0

enable_language(CUDA)

include(traccc-compiler-options-cuda)

find_package(CUDAToolkit REQUIRED)

add_library(
    traccc_tests_cuda_main
    STATIC
    cuda_main.cpp
)

target_link_libraries(
    traccc_tests_cuda_main
    PRIVATE
    CUDA::cudart
    GTest::gtest
)

traccc_add_test(
    cuda

    # Define the sources for the test.
    test_basic.cu
    test_cca.cpp
    test_copy_algs.cpp
    test_kalman_filter.cpp
    test_thrust.cu
    test_sync.cu

    LINK_LIBRARIES
    GTest::gtest
    vecmem::cuda
    detray::core
    detray::utils
    traccc::core
    traccc::device_common
    traccc::cuda
    traccc::performance
    traccc::io
    traccc_tests_cuda_main
    traccc_tests_common
)
