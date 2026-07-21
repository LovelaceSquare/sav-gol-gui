%% SavGol_test - Generate noisy spectra for Savitzky-Golay filtering.
%
% Creates spectra with varying noise levels but no NaN/Inf.
% Use as demo data for the SavGol Filtering GUI.
%
% Output variables:
%   spectra    - 35x600 matrix (samples x wavelengths)
%   wavelength - 1x600 vector (nm)
%
% Author: Lovelace's Square
% Date Created: 2026-03-16
% License: MIT
% Reviewed by Lovelace's Square: Yes
% Version: v 1.0

rng(42);

nSamples = 35;
nChannels = 600;
wavelength = linspace(800, 2500, nChannels);

gauss = @(x, mu, h, w) h .* exp(-((x - mu).^2) ./ (2*w.^2));

spectra = zeros(nSamples, nChannels);

for s = 1:nSamples
    % Clean signal with 5 absorption bands
    clean = 0.4 + gauss(wavelength, 1000, 0.6+0.1*randn(), 50) + ...
        gauss(wavelength, 1350, 0.9+0.1*randn(), 65) + ...
        gauss(wavelength, 1650, 1.1+0.15*randn(), 45) + ...
        gauss(wavelength, 1940, 0.7+0.1*randn(), 55) + ...
        gauss(wavelength, 2200, 0.8+0.1*randn(), 70);

    % Concentration variation
    clean = clean * (0.8 + 0.4*rand());

    % Variable noise level (some samples noisier than others)
    noiseLevel = 0.1 + 0.04*rand();
    noise = noiseLevel * randn(1, nChannels);

    % Slight baseline curvature
    t = linspace(0, 1, nChannels);
    baseline = 0.05*randn()*t + 0.03*randn()*t.^2;

    spectra(s, :) = clean + noise + baseline;
end

clearvars -except spectra wavelength

fprintf('Created: spectra (%dx%d), wavelength (1x%d)\n', ...
    size(spectra,1), size(spectra,2), length(wavelength));
fprintf('Contains variable noise levels across samples.\n');
fprintf('Run SavGol(spectra) to open the Savitzky-Golay GUI.\n');
