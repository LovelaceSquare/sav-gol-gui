classdef DataValidator
% DATAVALIDATOR Normalize and validate SavGol numeric and struct inputs.
%
%   normalize returns samples-by-channels data and a row-vector x-axis while
%   preserving optional source metadata. Validation methods return a boolean,
%   checked value where applicable, and a user-facing message.

    methods
        function [valid, normalized, message] = normalize(app, inputData, ...
                xAxisOverride, varName)
            % NORMALIZE Validate input and build the GUI data contract.
            %
            %   [valid, normalized, message] = normalize(inputData)
            %   accepts a numeric vector/matrix or a scalar struct. An
            %   optional xAxisOverride replaces an axis in the struct.
            if nargin < 3
                xAxisOverride = [];
            end
            if nargin < 4 || isempty(varName)
                varName = 'inputData';
            end

            valid = false;
            normalized = struct.empty;
            metadata = struct();
            sampleNames = [];

            if isnumeric(inputData)
                data = inputData;
                xAxis = [];
            elseif isstruct(inputData) && isscalar(inputData)
                [found, data] = app.firstField(inputData, ...
                    {'data', 'spectra', 'X', 'x'});
                if ~found
                    message = 'Input struct must contain a numeric data or spectra field.';
                    return;
                end
                [~, xAxis] = app.firstField(inputData, ...
                    {'wavelength', 'wavelengths', 'xAxis', 'xaxis', 'axis'});
                if isfield(inputData, 'metadata') && isstruct(inputData.metadata)
                    metadata = inputData.metadata;
                end
                if isfield(inputData, 'sampleNames')
                    sampleNames = inputData.sampleNames;
                end
                if isfield(inputData, 'varName') && ~isempty(inputData.varName)
                    varName = char(string(inputData.varName));
                end
            else
                message = 'Input must be a numeric matrix or a scalar struct.';
                return;
            end

            [validData, data, message] = app.validateMatrix(data);
            if ~validData
                return;
            end

            if ~isempty(xAxisOverride)
                xAxis = xAxisOverride;
            end
            if isempty(xAxis)
                xAxis = 1:size(data, 2);
            end
            [validAxis, xAxis, message] = app.validateAxis(xAxis, size(data, 2));
            if ~validAxis
                return;
            end

            normalized = struct();
            normalized.data = data;
            normalized.spectra = data;
            normalized.wavelength = xAxis;
            normalized.wavelengths = xAxis;
            normalized.varName = char(string(varName));
            normalized.metadata = metadata;
            if ~isempty(sampleNames)
                normalized.sampleNames = sampleNames;
            end
            valid = true;
            message = 'Validation passed.';
        end

        function [valid, data, message] = validateMatrix(~, data)
            % VALIDATEMATRIX Check and normalize a real finite matrix.
            valid = false;
            if ~isnumeric(data) || isempty(data) || ~ismatrix(data)
                message = 'Data must be a non-empty numeric 2-D matrix.';
                return;
            end
            if ~isreal(data)
                message = 'Data must be real.';
                return;
            end
            if any(~isfinite(data(:)))
                message = 'Data must not contain NaN or Inf values.';
                return;
            end

            data = double(data);
            if isvector(data)
                data = data(:)';
            end
            if size(data, 2) < 3
                message = 'Each signal must contain at least 3 points.';
                return;
            end
            valid = true;
            message = 'Validation passed.';
        end

        function [valid, xAxis, message] = validateAxis(~, xAxis, nChannels)
            % VALIDATEAXIS Check an optional finite monotonic x-axis.
            valid = false;
            if ~isnumeric(xAxis) || ~isreal(xAxis) || ~isvector(xAxis) || ...
                    numel(xAxis) ~= nChannels || any(~isfinite(xAxis(:)))
                message = sprintf( ...
                    'X-axis must be a real, finite vector with %d elements.', nChannels);
                return;
            end
            xAxis = double(xAxis(:)');
            differences = diff(xAxis);
            if any(differences == 0) || ...
                    ~(all(differences > 0) || all(differences < 0))
                message = 'X-axis values must be strictly monotonic.';
                return;
            end
            valid = true;
            message = 'Validation passed.';
        end

        function [valid, spacing, message] = uniformSpacing(~, xAxis)
            differences = diff(double(xAxis(:)'));
            spacing = mean(differences);
            scale = max(1, max(abs(differences)));
            tolerance = max(1e-9 * scale, 64 * eps(scale));
            valid = isfinite(spacing) && spacing ~= 0 && ...
                all(abs(differences - spacing) <= tolerance);
            if valid
                message = '';
            else
                message = ['Derivative filtering requires a uniformly spaced ' ...
                    'x-axis. Select column indices or a uniform axis vector.'];
            end
        end
    end

    methods (Access = private)
        function [found, value] = firstField(~, input, names)
            found = false;
            value = [];
            for index = 1:numel(names)
                if isfield(input, names{index}) && ~isempty(input.(names{index}))
                    found = true;
                    value = input.(names{index});
                    return;
                end
            end
        end
    end
end
