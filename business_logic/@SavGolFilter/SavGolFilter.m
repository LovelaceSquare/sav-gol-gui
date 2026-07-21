classdef SavGolFilter
% SAVGOLFILTER Toolbox-free Savitzky-Golay filtering.
%
%   This numerical class applies a centred least-squares polynomial to one
%   finite vector. It is used by the SavGol GUI and does not require a
%   toolbox. Coefficients are obtained from a Vandermonde fit centred at
%   zero. For derivative order d, factorial(d) converts the fitted
%   coefficient into a derivative and the returned coefficients are already
%   reversed for MATLAB convolution.
%
%   SEE ALSO: SavGol
%
%   Author: Lovelace's Square
%   License: MIT

    methods
        function [yFiltered, coefficients] = filter(app, y, windowSize, ...
                polyOrder, derivOrder, edgeMethod, xSpacing)
            % FILTER Smooth or differentiate one signal.
            %
            %   filtered = filter(y, windowSize, polyOrder, derivOrder, ...
            %       edgeMethod, xSpacing)
            %   [filtered, coefficients] = filter(...)
            %
            %   INPUTS:
            %       y           Finite real vector, row or column.
            %       windowSize  Odd integer >= 3 and <= numel(y).
            %       polyOrder   Integer from 0 through windowSize - 1.
            %       derivOrder  Integer from 0 through polyOrder.
            %       edgeMethod  none, reflection, replication, or
            %                   extrapolation.
            %       xSpacing    Optional finite nonzero signed spacing;
            %                   defaults to 1.
            %
            %   OUTPUTS:
            %       yFiltered   Filtered vector with input orientation.
            %       coefficients Convolution kernel with input orientation.
            if nargin < 7 || isempty(xSpacing)
                xSpacing = 1;
            end

            if ~isnumeric(y) || ~isvector(y) || isempty(y) || ~isreal(y) || ...
                    any(~isfinite(y(:)))
                error('SavGolFilter:InvalidSignal', ...
                    'Signal must be a non-empty, real, finite numeric vector.');
            end

            wasColumn = iscolumn(y);
            y = double(y(:)');
            [valid, message] = app.validateParams(windowSize, polyOrder, ...
                derivOrder, numel(y), xSpacing);
            if ~valid
                error('SavGolFilter:InvalidParameters', '%s', message);
            end
            edgeMethod = app.normalizeEdgeMethod(edgeMethod);

            halfWindow = (windowSize - 1) / 2;
            offsets = (-halfWindow:halfWindow)' .* xSpacing;
            vandermonde = offsets .^ (0:polyOrder);
            fitOperator = pinv(vandermonde);
            centreWeights = factorial(derivOrder) .* ...
                fitOperator(derivOrder + 1, :);

            % conv reverses its second input; reverse the centre weights so
            % odd derivatives retain their physical sign.
            coefficients = fliplr(centreWeights);

            switch edgeMethod
                case 'none'
                    yFiltered = conv(y, coefficients, 'same');

                case 'reflection'
                    left = y(halfWindow + 1:-1:2);
                    right = y(end - 1:-1:end - halfWindow);
                    yFiltered = app.filterExtended( ...
                        [left, y, right], coefficients, halfWindow);

                case 'replication'
                    left = repmat(y(1), 1, halfWindow);
                    right = repmat(y(end), 1, halfWindow);
                    yFiltered = app.filterExtended( ...
                        [left, y, right], coefficients, halfWindow);

                case 'extrapolation'
                    left = app.polynomialExtension(y(1:windowSize), ...
                        polyOrder, xSpacing, halfWindow, 'left');
                    right = app.polynomialExtension(y(end-windowSize+1:end), ...
                        polyOrder, xSpacing, halfWindow, 'right');
                    yFiltered = app.filterExtended( ...
                        [left, y, right], coefficients, halfWindow);
            end

            if wasColumn
                yFiltered = yFiltered(:);
                coefficients = coefficients(:);
            end
        end

        function [valid, message] = validateParams(~, windowSize, ...
                polyOrder, derivOrder, signalLength, xSpacing)
            if nargin < 5 || isempty(signalLength)
                signalLength = inf;
            end
            if nargin < 6 || isempty(xSpacing)
                xSpacing = 1;
            end

            valid = false;
            message = '';
            if ~SavGolFilter.isFiniteInteger(windowSize) || windowSize < 3
                message = 'Window size must be an integer of at least 3.';
            elseif mod(windowSize, 2) ~= 1
                message = 'Window size must be odd.';
            elseif ~isscalar(signalLength) || ~isnumeric(signalLength) || ...
                    isnan(signalLength) || signalLength < 1
                message = 'Signal length must be a positive scalar.';
            elseif windowSize > signalLength
                message = sprintf('Window size (%d) cannot exceed signal length (%d).', ...
                    windowSize, signalLength);
            elseif ~SavGolFilter.isFiniteInteger(polyOrder) || polyOrder < 0
                message = 'Polynomial order must be a non-negative integer.';
            elseif polyOrder >= windowSize
                message = 'Polynomial order must be less than window size.';
            elseif ~SavGolFilter.isFiniteInteger(derivOrder) || derivOrder < 0
                message = 'Derivative order must be a non-negative integer.';
            elseif derivOrder > polyOrder
                message = 'Derivative order must not exceed polynomial order.';
            elseif ~isnumeric(xSpacing) || ~isreal(xSpacing) || ...
                    ~isscalar(xSpacing) || ~isfinite(xSpacing) || xSpacing == 0
                message = 'X-axis spacing must be a finite, non-zero scalar.';
            else
                valid = true;
            end
        end

        function method = normalizeEdgeMethod(~, method)
            if isstring(method) && isscalar(method)
                method = char(method);
            end
            if ~ischar(method)
                error('SavGolFilter:InvalidEdgeMethod', ...
                    'Edge method must be text.');
            end

            method = lower(strtrim(method));
            switch method
                case {'none', 'zero', 'zeros'}
                    method = 'none';
                case {'reflection', 'reflect', 'mirror'}
                    method = 'reflection';
                case {'replication', 'replicate', 'nearest'}
                    method = 'replication';
                case {'extrapolation', 'extrapolate', 'polynomial'}
                    method = 'extrapolation';
                otherwise
                    error('SavGolFilter:InvalidEdgeMethod', ...
                        'Unknown edge method "%s".', method);
            end
        end
    end

    methods (Access = private)
        function yFiltered = filterExtended(~, extended, coefficients, halfWindow)
            filtered = conv(extended, coefficients, 'same');
            yFiltered = filtered(halfWindow + 1:end - halfWindow);
        end

        function extension = polynomialExtension(~, values, polyOrder, ...
                spacing, halfWindow, side)
            if strcmp(side, 'left')
                fitX = (0:numel(values) - 1)' .* spacing;
                queryX = (-halfWindow:-1)' .* spacing;
            else
                fitX = (-(numel(values) - 1):0)' .* spacing;
                queryX = (1:halfWindow)' .* spacing;
            end
            fitMatrix = fitX .^ (0:polyOrder);
            queryMatrix = queryX .^ (0:polyOrder);
            polynomial = fitMatrix \ double(values(:));
            extension = (queryMatrix * polynomial)';
        end
    end

    methods (Static, Access = private)
        function tf = isFiniteInteger(value)
            tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
                isfinite(value) && value == fix(value);
        end
    end
end
