# Project Chrono 9.0.1 core module (BSD-3-Clause) built as one static library, without Chrono's own
# top-level CMake (which copies ~1 GB of sample data and probes OpenMP, CUDA, MPI, ...).
# We feed src/chrono/CMakeLists.txt the few variables it expects and generate ChConfig.h and
# ChVersion.h ourselves: no optional module, no OpenMP, no SIMD intrinsics, no data files.
set(CHRONO_SRC "${CMAKE_CURRENT_SOURCE_DIR}/third_party/chrono")
set(CHRONO_VERSION "9.0.1")
set(CHRONO_VERSION_MAJOR 9)
set(CHRONO_VERSION_MINOR 0)
set(CHRONO_VERSION_PATCH 1)
set(CH_VERSION 0x00090001)
set(CHRONO_GEN "${CMAKE_CURRENT_BINARY_DIR}/chrono-gen")
file(MAKE_DIRECTORY "${CHRONO_GEN}/chrono")
foreach(v CASCADE IRRLICHT VSG MATLAB PARDISO_MKL MUMPS OPENGL PARSERS MULTICORE POSTPROCESS PYTHON VEHICLE FSI GPU
          SYNCHRONO SENSOR ROS MODAL FMI OMP_FOUND OMP_VERSION OMP_20 OMP_30 OMP_40 OPENMP_ENABLED TBB_ENABLED
          HAS_SSE SSE_LEVEL SSE_1_0 SSE_2_0 SSE_3_0 SSE_4_1 SSE_4_2 HAS_AVX AVX_LEVEL AVX_1_0 AVX_2_0 HAS_NEON HAS_FMA
          SIMD_ENABLED HAS_HDF5 HAS_CUDA CUDA_VERSION HAS_THRUST THRUST_VERSION HAS_GTEST HAS_GBENCHMARK COLLISION)
  set(CHRONO_${v} "#undef CHRONO_${v}")
endforeach()
configure_file("${CHRONO_SRC}/src/chrono/ChConfig.h.in" "${CHRONO_GEN}/chrono/ChConfig.h" @ONLY)
configure_file("${CHRONO_SRC}/src/chrono/ChVersion.h.in" "${CHRONO_GEN}/chrono/ChVersion.h" @ONLY)

include(CMakeDependentOption)
set(ENABLE_OPENMP OFF)
set(USE_BULLET_DOUBLE OFF)
set(USE_BULLET_OPENMP OFF)
set(BUILD_SHARED_LIBS OFF)
set(CH_LINKERFLAG_LIB "")
set(CMAKE_POSITION_INDEPENDENT_CODE OFF)
include_directories("${CHRONO_SRC}/src" "${CHRONO_GEN}" "${CMAKE_CURRENT_SOURCE_DIR}/third_party/eigen")
add_compile_definitions(CH_STATIC EIGEN_MPL2_ONLY EIGEN_DONT_PARALLELIZE)
if(WIN32 AND (MINGW OR CMAKE_COMPILER_IS_GNUCXX))
  add_compile_definitions(_MINGW _WINDOWS)
endif()
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wno-deprecated-declarations)
endif()
set(CH_COMPILER "COMPILER_GCC_X64")
add_subdirectory("${CHRONO_SRC}/src/chrono" chrono-core EXCLUDE_FROM_ALL)
# Chrono's TCP socket helpers are never used by the host and do not compile with MinGW
# (ChSocket.cpp: "size of array 'msgLength' is not an integral constant-expression"): drop them.
get_target_property(CHRONO_SOURCES ChronoEngine SOURCES)
list(FILTER CHRONO_SOURCES EXCLUDE REGEX "utils/ChSocket")
set_property(TARGET ChronoEngine PROPERTY SOURCES ${CHRONO_SOURCES})

add_library(lmphysics_chrono INTERFACE)
target_link_libraries(lmphysics_chrono INTERFACE ChronoEngine)
target_include_directories(lmphysics_chrono SYSTEM INTERFACE "${CHRONO_SRC}/src" "${CHRONO_GEN}" ${CH_INCLUDES}
                           "${CMAKE_CURRENT_SOURCE_DIR}/third_party/eigen")
target_compile_definitions(lmphysics_chrono INTERFACE CH_STATIC EIGEN_MPL2_ONLY EIGEN_DONT_PARALLELIZE)
if(WIN32)
  target_link_libraries(lmphysics_chrono INTERFACE winmm)  # timeGetTime in HACD's micro allocator
endif()
