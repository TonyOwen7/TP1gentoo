import sys
import os

base_dir = os.path.dirname(__file__)

paths = [
    os.path.join(base_dir, "data"),
    os.path.join(base_dir, "numbers"),
]

for p in paths:
    if p not in sys.path:
        sys.path.append(p)


import numpy as np
from sklearn.linear_model import LinearRegression
from prime_numbers import primes_array
from complex_numbers import first_n_non_primes
from data import power_arrays_stack  


# Data
n = 7
k = 7

x = power_arrays_stack(n, k)
y = [x**2 + 1 for x in range(1, n+1)]
print(x)
print(y)



# Fit regression
model = LinearRegression()
model.fit(x, y)

# R² from sklearn
r2 = model.score(x, y)

# Predictions
y_pred = model.predict(x)

# R as correlation between y and y_pred
R = np.corrcoef(y, y_pred)[0,1]

print("Intercept a:", model.intercept_)
print("Coefficients b:", model.coef_)
print("R²:", r2)
print("R :", R)
