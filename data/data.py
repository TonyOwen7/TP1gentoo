import numpy as np

def power_arrays_stack(n, k):
    """
    Generate k arrays where each array contains x**k for x in range(1, n+1).
    Returns a column stack of these arrays, or a single row array if k=1.
    
    Parameters:
    n (int): Upper limit for x values (inclusive)
    k (int): Number of arrays/power to raise x to
    
    Returns:
    numpy.ndarray: Column-stacked array of shape (n, k) if k>1, or shape (1, n) if k=1
    """
    if k == 1:
        # Special case: return single row array [0, 1, 2, ..., n-1]
        return np.array([[x for x in range(n)]])
    
    arrays = []
    for power in range(1, k + 1):
        array = [x**power for x in range(1, n + 1)]
        arrays.append(array)
    
    return np.column_stack(arrays)

