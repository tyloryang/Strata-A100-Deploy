import ctypes
import sys

D = "/data/Strata-0.2.20/engine-cuda12/"
rt = ctypes.CDLL(D + "libcudart.so.12")
rt.cudaGetErrorString.restype = ctypes.c_char_p


def err(rc):
    return rt.cudaGetErrorString(rc).decode()


v = ctypes.c_int()
rt.cudaRuntimeGetVersion(ctypes.byref(v))
print("runtime version", v.value)
rc = rt.cudaDriverGetVersion(ctypes.byref(v))
print("driver version", v.value, "rc", rc)

n = ctypes.c_int()
rc = rt.cudaGetDeviceCount(ctypes.byref(n))
print("cudaGetDeviceCount rc", rc, err(rc), "n", n.value)
if rc:
    sys.exit(1)

for i in range(n.value):
    rc1 = rt.cudaSetDevice(i)
    rc2 = rt.cudaFree(None)
    free = ctypes.c_size_t()
    tot = ctypes.c_size_t()
    rt.cudaMemGetInfo(ctypes.byref(free), ctypes.byref(tot))
    print(f"dev {i}: setDevice rc {rc1}, context rc {rc2} ({err(rc2)}), free {free.value >> 20} MiB / {tot.value >> 20} MiB")
    if rc2:
        sys.exit(2)

    bl = ctypes.CDLL(D + "libcublas.so.12")
    h = ctypes.c_void_p()
    rc = bl.cublasCreate_v2(ctypes.byref(h))
    print(f"dev {i}: cublasCreate rc {rc}")
    if rc:
        sys.exit(3)
    p = [ctypes.c_void_p() for _ in range(3)]
    for x in p:
        rt.cudaMalloc(ctypes.byref(x), 256 * 256 * 4)
        rt.cudaMemset(x, 0, 256 * 256 * 4)
    one = ctypes.c_float(1.0)
    zero = ctypes.c_float(0.0)
    rc = bl.cublasSgemm_v2(h, 0, 0, 256, 256, 256, ctypes.byref(one), p[0], 256, p[1], 256,
                           ctypes.byref(zero), p[2], 256)
    rcs = rt.cudaDeviceSynchronize()
    print(f"dev {i}: cublasSgemm rc {rc}, sync rc {rcs} ({err(rcs)})")
    for x in p:
        rt.cudaFree(x)
    bl.cublasDestroy_v2(h)
    if rc or rcs:
        sys.exit(4)

print("CUDA-PROBE-OK")
