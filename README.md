# SavGol

Savitzky-Golay smoothing moves a small window along each row, fits a polynomial
to the values inside the window, and uses the fitted polynomial to replace the
centre value. This keeps broad peaks and trends while reducing short-scale
noise. The same fit can also provide a derivative. Rows are samples and
columns are channels.

The SavGol app lets users choose the window, polynomial, derivative, and edge
settings, inspect individual samples, apply the calculation to all rows, and
export the result.

## Start

```matlab
addpath('path/to/SavGol')
SavGol_test
app = SavGol(spectra);
```

The constructor accepts a numeric vector or matrix, or a struct with
`data`/`spectra` and an optional `wavelength`/`wavelengths`/`xAxis` field.
Rows are samples and columns are channels. A numeric vector becomes one row;
matrices are not transposed.

## Parameters

| Parameter | Rule | Default |
|---|---|---:|
| Window size | Odd integer, at least 3, no longer than the signal | 11 |
| Polynomial order | Integer from 0 through `windowSize - 1` | 3 |
| Derivative order | Integer from 0 through `min(polyOrder, 3)` | 0 |
| Edge method | `extrapolation`, `reflection`, `replication`, or `none` | `extrapolation` |

The window uses natural window-size steps and adapts its limits to the loaded
signal. The derivative order is limited to 3. The sample selector changes the
displayed row only; `Apply` processes every row.

`reflection` mirrors samples without repeating the endpoint. `replication`
repeats endpoint values. `none` uses zero extension. `extrapolation` extends
a polynomial fitted at each edge.

For derivatives, the x-axis must increase or decrease at a constant spacing.
Its signed spacing determines the derivative units and sign, including for a
descending axis. Smoothing without derivatives does not need equal spacing.

## Use the calculation without the window

```matlab
addpath(fullfile('path/to/SavGol', 'business_logic'))
filter = SavGolFilter();

% First derivative with 0.25 x-units between channels:
dy = filter.filter(y, 11, 3, 1, 'extrapolation', 0.25);
```

The result keeps the row or column shape of the input. The second output is
the convolution kernel used by the fit.

## Result

After `Apply`, `app.getData()` returns:

- `data` and `spectra`: filtered samples-by-channels matrix
- `wavelength` and `wavelengths`: x-axis values
- `metadata`: method, window, polynomial order, derivative order, edge method,
  spacing, and application time
- `isCurrent`: false after parameters or input data change

Export uses the same data and x-axis values. Preview sampling does not change
the full result.

## Example data and checks

`SavGol_test.m` creates `spectra` and `wavelength` with different noise levels:

```matlab
SavGol_test
app = SavGol(spectra);
```

Run Code Analyzer from this folder:

```matlab
checkcode('SavGol.m', '-id')
checkcode('business_logic/@SavGolFilter/SavGolFilter.m', '-id')
checkcode('business_logic/@DataValidator/DataValidator.m', '-id')
```

MATLAB R2022a or later is required. No additional toolbox is needed.

## Reference

Savitzky, A. and Golay, M. J. E. (1964). Smoothing and differentiation of data
by simplified least squares procedures. *Analytical Chemistry*, 36(8),
1627-1639.

License: MIT
