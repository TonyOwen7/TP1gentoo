import numpy as np

def is_prime(x):
    if x < 2:
        return False
    for i in range(2, int(x**0.5) + 1):
        if x % i == 0:
            return False
    return True

def first_n_non_primes(n):
    non_primes = []
    num = 1
    while len(non_primes) < n:
        if not is_prime(num):
            non_primes.append(num)
        num += 1
    return np.array(non_primes)
