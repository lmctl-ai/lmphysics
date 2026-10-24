# Linux glibc policy (Rule 14)

From v0.1.3, Linux uses dynamic glibc >= 2.35. ChronoEngine is built static, with bundled Bullet and header-only Eigen; optional modules, OpenMP and Eigen parallelism stay disabled. Linux library searches are limited to .a. libstdc++ and libgcc remain static, and full -static is used only on Windows. macOS keeps its existing system-library policy.

Both Linux CI jobs build on Ubuntu 22.04. test.sh runs eight checker regressions, requires dynamic libc.so.6 and allows only glibc library/loader names. readelf checks the GLIBC <= 2.35 symbol ceiling; if unavailable, ldd checks names/missing dependencies and explicitly says the symbol-version audit needs readelf. No relink-object archive is generated or shipped. --version stays exactly lmphysics X.Y.Z for installer compatibility.

Local verification: all 19 test.sh checks pass, including all 35 self-contained examples, 40 gallery images, 106 byte-identical result files, pose-bridge checks and 40 error cases. Extra fresh-directory README runs pass for pendulum, bounce and gear_train with build/lmphysics and published lmplot v0.2.1. Linux x64 is 9,408,352 bytes, with NEEDED libm.so.6, libc.so.6, ld-linux-x86-64.so.2 and maximum GLIBC_2.34. The supported release baseline remains glibc >= 2.35.
