/*-------------------------------------------------------------------------
 *
 * gpuqo_bit_manipulation.cuh
 *	  bit manipulation functions using BMI/BMI2 or emulation.
 *
 * src/optimizer/gpuqo/gpuqo_bit_manipulation.cuh
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_BIT_MANIPULATION_CUH
#define GPUQO_BIT_MANIPULATION_CUH

#include <cstdint>

#ifdef __BMI2__
#include <immintrin.h>
#endif

#ifdef __CUDA_ARCH__

template<typename T>
__device__ 
inline int popc(T x){
    if (sizeof(T) == 4)
        return __popc(x);
    else 
        return __popcll(x);
}

#else

template<typename T>
__host__ 
inline int popc(T x){
    if (sizeof(T) == 4)
        return __builtin_popcount(x);
    else 
        return __builtin_popcountll(x);
}

#endif

#ifdef __CUDA_ARCH__

template<typename T>
__device__ 
inline int ffs(T x){
    if (sizeof(T) == 4)
        return __ffs(x);
    else 
        return __ffsll(x);
}

#else

template<typename T>
__host__ 
inline int ffs(T x){
    if (sizeof(T) == 4)
        return __builtin_ffs(x);
    else 
        return __builtin_ffsll(x);
}

#endif

#ifdef __CUDA_ARCH__

template<typename T>
__device__ 
inline int clz(T x){
    if (sizeof(T) == 4)
        return __clz(x);
    else 
        return __clzll(x);
}

#else

template<typename T>
__host__ 
inline int clz(T x){
    if (sizeof(T) == 4)
        return __builtin_clz(x);
    else 
        return __builtin_clzll(x);
}

#endif

/* 
 * PDEP
 * 
 * Deposit contiguous low bits from integer a to dst at the corresponding bit
 * locations specified by mask; all other bits in dst are set to zero.
 */
 
#if !(defined __BMI2__) || (defined __CUDA_ARCH__)

template<typename T>
__host__ __device__
inline T pdep(T a, T mask){
    T res = 0;
    for (T bb = 1; mask; bb += bb) {
        if (a & bb)
            res |= mask & -mask;
        mask &= mask - 1;
  }
  return res;
}

#else

template<typename T>
inline T pdep(T a, T mask){
    if (sizeof(T) == 4)
        return _pdep_u32(a, mask);
    else
        return _pdep_u64(a, mask);
}

#endif

/* 
 * BLSI
 * 
 * Extract the lowest set bit from integer a and set the corresponding bit in 
 * dst. All other bits in dst are zeroed, and all bits are zeroed if no bits
 * are set in a.
 */
 
#if !(defined __BMI2__) || (defined __CUDA_ARCH__)

template<typename T>
__host__ __device__
inline T blsi(T a){
    return a & (-a);
}

#else

template<typename T>
inline T blsi(T a){
    if (sizeof(T) == 4)
        return _blsi_u32(a);
    else
        return _blsi_u64(a);    
}

#endif

/* 
 * BLSMSK
 * 
 * Set all the lower bits of dst up to and including the lowest set bit in 
 * unsigned 32-bit integer a.
 */
 
#if !(defined __BMI2__) || (defined __CUDA_ARCH__)

template<typename T>
__host__ __device__
inline T blsmsk(T a){
    return a ^ (a - 1);
}

#else

template<typename T>
inline T blsmsk(T a){
    if (sizeof(T) == 4)
        return _blsmsk_u32(a);
    else
        return _blsmsk_u64(a);
}

#endif

/* 
 * BLSR
 * 
 * Copy all bits from integer a to dst, and reset (set to 0) the bit in dst 
 * that corresponds to the lowest set bit in a.
 */
 
#if !(defined __BMI2__) || (defined __CUDA_ARCH__)

template<typename T>
__host__ __device__
inline T blsr(T a){
    return a & (a - 1);
}

#else

template<typename T>
inline T blsr(T a){
    if (sizeof(T) == 4)
        return _blsr_u32(a);
    else
        return _blsr_u64(a);    
}

#endif

template<typename T>
__host__ __device__
inline T floorPow2(T a){
    int pos = sizeof(T)*8 - clz(a) - 1;
    return ((T)1) << pos;
}

template<typename T>
__host__ __device__
inline T ceilPow2(T a){
    T fa = floorPow2(a);
    if (a == fa)
        return fa;
    else
        return fa<<1;
}

#endif							/* GPUQO_BIT_MANIPULATION_CUH */