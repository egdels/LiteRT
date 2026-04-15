# Stub build_defs.bzl for local_config_cuda when CUDA is not available.

def if_cuda(if_true, if_false = []):
    return if_false

def if_cuda_is_configured(x):
    return []

def cuda_default_copts():
    return []

def cuda_gpu_architectures():
    return []
