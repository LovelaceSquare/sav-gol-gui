classdef SavGol < matlab.apps.AppBase
% SAVGOL Interactive Savitzky-Golay smoothing and derivative GUI.
%
%   SavGol smooths spectral data with a moving polynomial fit. For each row,
%   it fits a polynomial to the values in a small window and uses the fitted
%   centre value as the smoothed result. The same fit can calculate a
%   derivative. Rows are samples and columns are channels.
%
%   The SavGol app lets users choose the window, polynomial, derivative, and
%   edge settings, inspect individual samples, apply the calculation to all
%   rows, and export the result. The calculation is also available through
%   SavGolFilter.
%
%   USAGE:
%       app = SavGol();
%       app = SavGol(spectra);
%       app = SavGol(struct('data', spectra, 'wavelength', wavelength));
%
%   INPUTS:
%       spectra     Numeric, real, finite vector or matrix. A vector becomes
%                   one row; matrix rows remain samples.
%       input       Scalar struct with data/spectra and an optional
%                   wavelength/wavelengths/xAxis/axis field.
%
%   INPUT AND OUTPUT COMMANDS:
%       app.setInputData(input)  Load and validate data programmatically.
%       app.getData()            Return the current filtered result.
%       delete(app)               Close the application safely.
%
%   EXAMPLE:
%       SavGol_test
%       input.data = spectra;
%       input.wavelength = wavelength;
%       app = SavGol(input);
%       % Choose a sample and parameters in the preview, then click Apply.
%       result = app.getData();
%
%   PARAMETERS:
%       windowSize  Odd integer >= 3 and no longer than the signal.
%       polyOrder   Integer from 0 through windowSize - 1.
%       derivOrder  Integer from 0 through min(polyOrder, 3) in the GUI.
%       edgeMethod  Extrapolation, reflection, replication, or none.
%
%   SEE ALSO: SavGolFilter, DataValidator
%
%   Author: Lovelace's Square
%   Affiliation: Lovelace's Square
%   Date Created: 2026-03-16
%   License: MIT
%   Version: v 1.0

    properties (Access = public)
        UIFigure matlab.ui.Figure
        HTMLComponent matlab.ui.control.HTML
    end

    properties (Access = private)
        Filter
        Validator
        InputData struct = struct.empty
        ProcessedData struct = struct.empty
        AppliedParams struct = struct.empty
        LoadedVarName char = ''
        DataLoaded logical = false
        SelectedSampleIndex double = 1
        ResultIsCurrent logical = false
        UiReady logical = false
        IsClosed logical = false
        ResponseCounter double = 0
        PendingPayload struct = struct.empty
        MaxDirectPlotElements double = 500000
        MaxPlotSamples double = 5000
        MaxPlotWavelengths double = 100
        MaxPlotBytes double = 1024^3
    end

    methods (Access = public)
        function app = SavGol(inputData)
            createComponents(app);
            initializeBusinessLogic(app);
            registerApp(app, app.UIFigure);

            if nargin >= 1 && ~isempty(inputData)
                try
                    setInputData(app, inputData);
                catch ME
                    warning('SavGol:InputError', ...
                        'Could not load input data: %s', ME.message);
                end
            end

            runStartupFcn(app, @startupFcn);
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            % DELETE Close the SavGol window and release UI resources.
            app.IsClosed = true;
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            screenSize = get(0, 'ScreenSize');
            width = min(1400, round(screenSize(3) * 0.8));
            height = min(900, round(screenSize(4) * 0.85));

            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 width height];
            app.UIFigure.Name = 'Savitzky-Golay Filter';
            app.UIFigure.Color = [0.91 0.92 0.93];
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.CloseRequestFcn = ...
                createCallbackFcn(app, @closeRequest, true);
            app.UIFigure.SizeChangedFcn = ...
                createCallbackFcn(app, @figureSizeChanged, true);

            modulePath = fileparts(mfilename('fullpath'));
            app.HTMLComponent = uihtml(app.UIFigure);
            app.HTMLComponent.Position = [1 1 width height];
            app.HTMLComponent.HTMLSource = fullfile( ...
                modulePath, 'ui', 'savgol_ui.html');
            app.HTMLComponent.DataChangedFcn = ...
                createCallbackFcn(app, @HTMLDataChanged, true);
            app.UIFigure.Visible = 'on';
        end

        function initializeBusinessLogic(app)
            modulePath = fileparts(mfilename('fullpath'));
            addpath(fullfile(modulePath, 'business_logic'));
            app.Filter = SavGolFilter();
            app.Validator = DataValidator();
        end

        function startupFcn(app)
            movegui(app.UIFigure, 'center');
        end

        function figureSizeChanged(app, ~)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure)
                return;
            end
            position = app.UIFigure.Position;
            if ~isempty(app.HTMLComponent) && isvalid(app.HTMLComponent)
                app.HTMLComponent.Position = [1 1 position(3) position(4)];
            end
        end

        function closeRequest(app, ~)
            app.IsClosed = true;
            delete(app);
        end
    end

    methods (Access = private)
        function HTMLDataChanged(app, ~)
            data = app.HTMLComponent.Data;
            if isempty(data) || ~isstruct(data)
                return;
            end
            if isfield(data, 'source') && strcmp(data.source, 'matlab')
                return;
            end
            if ~isfield(data, 'action')
                return;
            end

            action = char(string(data.action));
            switch action
                case 'uiReady'
                    handleUiReady(app);
                case {'loadData', 'load_data'}
                    handleLoadData(app);
                case {'loadVariable', 'load_variable'}
                    handleLoadVariable(app, data);
                case 'preview'
                    handlePreview(app, data);
                case {'getSpectrum', 'getSample'}
                    handleGetSpectrum(app, data);
                case 'apply'
                    handleApply(app, data);
                case {'prepareExport', 'export'}
                    handlePrepareExport(app);
                case {'doExport', 'do_export'}
                    handleDoExport(app, data);
                case {'plotOption', 'plot_option'}
                    handlePlotOption(app, data);
                otherwise
                    sendResponse(app, 'error', struct( ...
                        'message', sprintf('Unknown action: %s', action)));
            end
        end

        function handleUiReady(app)
            app.UiReady = true;
            if ~isempty(app.PendingPayload)
                payload = app.PendingPayload;
                app.PendingPayload = struct.empty;
                sendResponse(app, 'dataLoaded', payload);
            else
                sendResponse(app, 'ready', struct( ...
                    'message', 'Ready. Load spectral data to begin.'));
            end
        end

        function handleLoadData(app)
            variables = collectWorkspaceInputs(app);
            vectors = collectWorkspaceVectors(app);
            if isempty(variables)
                sendResponse(app, 'error', struct('message', ...
                    'No compatible numeric matrices or data structs found.'));
                return;
            end
            sendResponse(app, 'showVarList', struct( ...
                'variables', {variables}, 'vectors', {vectors}));
        end

        function handleLoadVariable(app, request)
            if ~isfield(request, 'varName')
                sendResponse(app, 'error', struct('message', ...
                    'Missing workspace variable name.'));
                return;
            end
            varName = char(string(request.varName));
            if ~isvarname(varName) || ...
                    ~evalin('base', sprintf('exist(''%s'', ''var'')', varName))
                sendResponse(app, 'error', struct('message', ...
                    sprintf('Workspace variable "%s" was not found.', varName)));
                return;
            end

            xAxis = [];
            if isfield(request, 'xAxisVar') && ~isempty(request.xAxisVar)
                axisName = char(string(request.xAxisVar));
                if ~isvarname(axisName) || ...
                        ~evalin('base', sprintf('exist(''%s'', ''var'')', axisName))
                    sendResponse(app, 'error', struct('message', ...
                        sprintf('X-axis variable "%s" was not found.', axisName)));
                    return;
                end
                xAxis = evalin('base', axisName);
            end

            raw = evalin('base', varName);
            [valid, normalized, message] = app.Validator.normalize( ...
                raw, xAxis, varName);
            if ~valid
                sendResponse(app, 'error', struct('message', message));
                return;
            end
            normalized.varName = varName;
            loadNormalizedData(app, normalized);
            deliverDataLoaded(app, buildDataLoadedPayload(app));
        end

        function handlePreview(app, request)
            if ~app.DataLoaded
                sendResponse(app, 'error', struct('message', 'Load data first.'));
                return;
            end

            [valid, params, message] = parseParams(app, request);
            if ~isempty(app.ProcessedData) && ...
                    (~valid || ~paramsMatch(app, params, app.AppliedParams))
                markResultStale(app);
            end
            if ~valid
                sendResponse(app, 'error', struct('message', message));
                return;
            end

            sampleIndex = round(safeDouble(app, request, ...
                'sampleIndex', app.SelectedSampleIndex));
            [nSamples, ~] = size(app.InputData.data);
            sampleIndex = max(1, min(nSamples, sampleIndex));
            app.SelectedSampleIndex = sampleIndex;
            original = app.InputData.data(sampleIndex, :);
            filtered = app.Filter.filter(original, params.windowSize, ...
                params.polyOrder, params.derivOrder, params.edgeMethod, ...
                params.xSpacing);
            payload = params;
            payload.wavelength = app.InputData.wavelength;
            payload.original = original;
            payload.filtered = filtered;
            payload.sampleIndex = sampleIndex;
            payload.sampleName = sampleName(app, sampleIndex);
            payload.nSamples = nSamples;
            payload.resultCurrent = app.ResultIsCurrent;
            payload.statusMessage = sprintf( ...
                'Preview: window %d, polynomial %d, derivative %d, %s edges.', ...
                params.windowSize, params.polyOrder, params.derivOrder, ...
                params.edgeMethod);
            if isfield(request, 'requestId')
                payload.requestId = request.requestId;
            end
            sendResponse(app, 'previewUpdated', payload);
        end

        function handleGetSpectrum(app, request)
            if ~app.DataLoaded
                sendResponse(app, 'error', struct('message', 'Load data first.'));
                return;
            end
            if isfield(request, 'sampleIndex')
                fieldName = 'sampleIndex';
            else
                fieldName = 'signalIndex';
            end
            index = round(safeDouble(app, request, fieldName, ...
                app.SelectedSampleIndex));
            [nSamples, ~] = size(app.InputData.data);
            app.SelectedSampleIndex = max(1, min(nSamples, index));
            handlePreview(app, request);
        end

        function handleApply(app, request)
            if ~app.DataLoaded
                sendResponse(app, 'error', struct('message', 'Load data first.'));
                return;
            end
            [valid, params, message] = parseParams(app, request);
            if ~valid
                sendResponse(app, 'error', struct('message', message));
                return;
            end

            spectra = app.InputData.data;
            [nSamples, nChannels] = size(spectra);
            filtered = zeros(nSamples, nChannels);
            progressStep = max(1, floor(nSamples / 20));
            sendResponse(app, 'progress', struct( ...
                'title', 'Applying Savitzky-Golay filter...', ...
                'current', 0, 'total', nSamples));
            drawnow limitrate;

            for row = 1:nSamples
                filtered(row, :) = app.Filter.filter(spectra(row, :), ...
                    params.windowSize, params.polyOrder, params.derivOrder, ...
                    params.edgeMethod, params.xSpacing);
                if mod(row, progressStep) == 0 || row == nSamples
                    sendResponse(app, 'progress', struct( ...
                        'title', 'Applying Savitzky-Golay filter...', ...
                        'current', row, 'total', nSamples));
                    drawnow limitrate;
                end
            end

            metadata = struct();
            metadata.method = 'SavitzkyGolay';
            metadata.windowSize = params.windowSize;
            metadata.polyOrder = params.polyOrder;
            metadata.derivOrder = params.derivOrder;
            metadata.edgeMethod = params.edgeMethod;
            metadata.xSpacing = params.xSpacing;
            metadata.applied = datetime('now');
            if isfield(app.InputData, 'metadata') && ...
                    ~isempty(fieldnames(app.InputData.metadata))
                metadata.originalMetadata = app.InputData.metadata;
            end

            output = struct();
            output.data = filtered;
            output.spectra = filtered;
            output.wavelength = app.InputData.wavelength;
            output.wavelengths = app.InputData.wavelength;
            output.varName = app.LoadedVarName;
            output.metadata = metadata;
            output.isCurrent = true;
            if isfield(app.InputData, 'sampleNames')
                output.sampleNames = app.InputData.sampleNames;
            end
            app.ProcessedData = output;
            app.AppliedParams = params;
            app.ResultIsCurrent = true;

            payload = params;
            payload.message = sprintf('Filtered %d spectra (%d channels).', ...
                nSamples, nChannels);
            payload.statusMessage = payload.message;
            payload.nSamples = nSamples;
            payload.nChannels = nChannels;
            payload.wavelength = app.InputData.wavelength;
            selectedIndex = max(1, min(nSamples, app.SelectedSampleIndex));
            payload.sampleIndex = selectedIndex;
            payload.sampleName = sampleName(app, selectedIndex);
            payload.selectedFiltered = filtered(selectedIndex, :);
            payload.resultCurrent = true;
            payload.tooLarge = numel(filtered) > app.MaxDirectPlotElements;
            payload.memoryBytes = estimatePlotBytes(app, nSamples, nChannels);
            payload.memoryLimitBytes = app.MaxPlotBytes;
            if ~payload.tooLarge
                payload.spectra = filtered;
                payload.plotNote = sprintf('Showing all %d filtered spectra.', nSamples);
            else
                payload.plotNote = sprintf( ...
                    'Showing selected sample %d of %d filtered spectra.', ...
                    selectedIndex, nSamples);
            end
            sendResponse(app, 'filterApplied', payload);
        end

        function handlePrepareExport(app)
            if isempty(app.ProcessedData) || ~app.ResultIsCurrent
                sendResponse(app, 'error', struct('message', ...
                    'Apply the current parameters before exporting.'));
                return;
            end
            existingNames = evalin('base', 'who');
            suggested = suggestName(app, existingNames, 'savGolFilteredData');
            sendResponse(app, 'showExportDialog', struct( ...
                'suggestedName', suggested));
        end

        function handleDoExport(app, request)
            if isempty(app.ProcessedData) || ~app.ResultIsCurrent
                sendResponse(app, 'error', struct('message', ...
                    'The result is missing or stale. Apply before exporting.'));
                return;
            end
            if ~isfield(request, 'varName')
                sendResponse(app, 'error', struct('message', ...
                    'Enter an export variable name.'));
                return;
            end
            varName = strtrim(char(string(request.varName)));
            if ~isvarname(varName)
                sendResponse(app, 'error', struct('message', ...
                    sprintf('Invalid MATLAB variable name: %s', varName)));
                return;
            end
            assignin('base', varName, app.ProcessedData);
            sendResponse(app, 'exportCompleted', struct( ...
                'exportedName', varName, ...
                'message', sprintf('Exported "%s" to the workspace.', varName)));
        end

        function handlePlotOption(app, request)
            if isempty(app.ProcessedData) || ~app.ResultIsCurrent
                sendResponse(app, 'error', struct('message', ...
                    'Apply the current parameters before plotting results.'));
                return;
            end
            mode = '';
            if isfield(request, 'mode')
                mode = lower(char(string(request.mode)));
            end
            spectra = app.ProcessedData.data;
            wavelength = app.ProcessedData.wavelength;
            [nSamples, nChannels] = size(spectra);

            switch mode
                case 'none'
                    sendResponse(app, 'plotDisabled', struct( ...
                        'message', 'Result plot disabled.'));
                case 'all'
                    if estimatePlotBytes(app, nSamples, nChannels) > app.MaxPlotBytes
                        sendResponse(app, 'error', struct('message', ...
                            'Plot payload exceeds 1 GB. Use every-N plotting.'));
                        return;
                    end
                    sendResponse(app, 'plotData', struct( ...
                        'spectra', spectra, 'wavelength', wavelength, ...
                        'plotNote', sprintf('Showing all %d spectra.', nSamples)));
                case 'every'
                    step = max(1, round(safeDouble(app, request, 'step', 1)));
                    rowIndex = 1:step:nSamples;
                    columnStep = max(1, ceil(nChannels / app.MaxPlotWavelengths));
                    columnIndex = 1:columnStep:nChannels;
                    if numel(rowIndex) > app.MaxPlotSamples
                        rowIndex = rowIndex(1:ceil(numel(rowIndex) / ...
                            app.MaxPlotSamples):end);
                    end
                    sampled = spectra(rowIndex, columnIndex);
                    if estimatePlotBytes(app, size(sampled, 1), ...
                            size(sampled, 2)) > app.MaxPlotBytes
                        sendResponse(app, 'error', struct('message', ...
                            'Sampled plot is still too large. Increase the step.'));
                        return;
                    end
                    note = sprintf('Showing %d of %d spectra', ...
                        size(sampled, 1), nSamples);
                    if columnStep > 1
                        note = sprintf('%s; every %dth channel.', note, columnStep);
                    else
                        note = [note '.'];
                    end
                    sendResponse(app, 'plotData', struct( ...
                        'spectra', sampled, ...
                        'wavelength', wavelength(columnIndex), ...
                        'plotNote', note));
                otherwise
                    sendResponse(app, 'error', struct('message', ...
                        sprintf('Unknown plot mode: %s', mode)));
            end
        end

    end

    methods (Access = private)
        function [valid, params, message] = parseParams(app, request)
            params = struct();
            params.windowSize = round(safeDouble(app, request, ...
                'windowSize', defaultWindow(app)));
            params.polyOrder = round(safeDouble(app, request, 'polyOrder', 3));
            params.derivOrder = min(3, round(safeDouble(app, request, 'derivOrder', 0)));
            params.edgeMethod = 'extrapolation';
            if isfield(request, 'edgeMethod')
                params.edgeMethod = char(string(request.edgeMethod));
            end
            try
                params.edgeMethod = app.Filter.normalizeEdgeMethod( ...
                    params.edgeMethod);
            catch ME
                valid = false;
                message = ME.message;
                params.xSpacing = 1;
                return;
            end

            [uniform, spacing, spacingMessage] = ...
                app.Validator.uniformSpacing(app.InputData.wavelength);
            if params.derivOrder > 0 && ~uniform
                valid = false;
                message = spacingMessage;
                params.xSpacing = 1;
                return;
            end
            if uniform
                params.xSpacing = spacing;
            else
                params.xSpacing = 1;
            end
            [valid, message] = app.Filter.validateParams( ...
                params.windowSize, params.polyOrder, params.derivOrder, ...
                size(app.InputData.data, 2), params.xSpacing);
        end

        function value = safeDouble(~, input, field, defaultValue)
            value = defaultValue;
            if ~isstruct(input) || ~isfield(input, field)
                return;
            end
            raw = input.(field);
            if (isnumeric(raw) || islogical(raw)) && isscalar(raw) && isfinite(raw)
                value = double(raw);
            elseif ischar(raw) || (isstring(raw) && isscalar(raw))
                parsed = str2double(raw);
                if isfinite(parsed)
                    value = parsed;
                end
            end
        end

        function windowSize = defaultWindow(app)
            nChannels = size(app.InputData.data, 2);
            windowSize = min(11, nChannels);
            if mod(windowSize, 2) == 0
                windowSize = windowSize - 1;
            end
        end

        function payload = buildDataLoadedPayload(app)
            windowSize = defaultWindow(app);
            polyOrder = min(3, windowSize - 1);
            params = struct('windowSize', windowSize, ...
                'polyOrder', polyOrder, 'derivOrder', 0, ...
                'edgeMethod', 'extrapolation');
            [uniform, spacing] = ...
                app.Validator.uniformSpacing(app.InputData.wavelength);
            if ~uniform
                spacing = 1;
            end
            params.xSpacing = spacing;

            [nSamples, nChannels] = size(app.InputData.data);
            app.SelectedSampleIndex = max(1, min(nSamples, app.SelectedSampleIndex));
            sampleSpectrum = app.InputData.data(app.SelectedSampleIndex, :);
            preview = app.Filter.filter(sampleSpectrum, windowSize, ...
                polyOrder, 0, 'extrapolation', spacing);

            payload = params;
            payload.message = sprintf('Loaded "%s" (%d x %d).', ...
                app.LoadedVarName, nSamples, nChannels);
            payload.statusMessage = payload.message;
            payload.varName = app.LoadedVarName;
            payload.nSamples = nSamples;
            payload.nChannels = nChannels;
            payload.maxWindow = nChannels - mod(nChannels + 1, 2);
            payload.wavelength = app.InputData.wavelength;
            payload.sampleIndex = app.SelectedSampleIndex;
            payload.sampleName = sampleName(app, app.SelectedSampleIndex);
            payload.sampleSpectrum = sampleSpectrum;
            payload.previewFiltered = preview;
            payload.axisUniform = uniform;
            payload.resultCurrent = false;
            if isfield(app.InputData, 'sampleNames')
                payload.sampleNames = app.InputData.sampleNames;
            end
            if numel(app.InputData.data) <= app.MaxDirectPlotElements
                payload.allSpectra = app.InputData.data;
            end
        end

        function loadNormalizedData(app, normalized)
            app.InputData = normalized;
            app.LoadedVarName = normalized.varName;
            app.DataLoaded = true;
            app.ProcessedData = struct.empty;
            app.AppliedParams = struct.empty;
            app.ResultIsCurrent = false;
            app.SelectedSampleIndex = 1;
        end

        function name = sampleName(app, index)
            name = '';
            if ~isfield(app.InputData, 'sampleNames') || ...
                    isempty(app.InputData.sampleNames)
                return;
            end
            names = app.InputData.sampleNames;
            if iscell(names)
                if index <= numel(names)
                    name = char(string(names{index}));
                end
            elseif isstring(names)
                if index <= numel(names)
                    name = char(names(index));
                end
            elseif ischar(names)
                if size(names, 1) >= index
                    name = strtrim(names(index, :));
                end
            end
        end

        function deliverDataLoaded(app, payload)
            if app.UiReady
                sendResponse(app, 'dataLoaded', payload);
            else
                app.PendingPayload = payload;
            end
        end

        function markResultStale(app)
            app.ResultIsCurrent = false;
            if ~isempty(app.ProcessedData)
                app.ProcessedData.isCurrent = false;
            end
        end

        function match = paramsMatch(~, left, right)
            if isempty(left) || isempty(right)
                match = false;
                return;
            end
            match = left.windowSize == right.windowSize && ...
                left.polyOrder == right.polyOrder && ...
                left.derivOrder == right.derivOrder && ...
                strcmp(left.edgeMethod, right.edgeMethod) && ...
                abs(left.xSpacing - right.xSpacing) <= ...
                    eps(max(abs([left.xSpacing right.xSpacing])));
        end

        function variables = collectWorkspaceInputs(app)
            workspace = evalin('base', 'whos');
            variables = {};
            numericClasses = {'double','single','int8','int16','int32', ...
                'int64','uint8','uint16','uint32','uint64'};
            for index = 1:numel(workspace)
                info = workspace(index);
                if info.global
                    continue;
                end
                if ismember(info.class, numericClasses) && numel(info.size) == 2
                    rows = info.size(1);
                    columns = info.size(2);
                    if rows == 1 || columns == 1
                        channels = max(rows, columns);
                        rows = 1;
                    else
                        channels = columns;
                    end
                    if channels >= 3
                        variables{end + 1} = struct( ...
                            'name', info.name, 'rows', rows, 'cols', channels, ...
                            'size', sprintf('%d x %d', rows, channels)); %#ok<AGROW>
                    end
                elseif strcmp(info.class, 'struct')
                    try
                        raw = evalin('base', info.name);
                        [valid, normalized] = app.Validator.normalize( ...
                            raw, [], info.name);
                    catch
                        valid = false;
                    end
                    if valid
                        [rows, channels] = size(normalized.data);
                        variables{end + 1} = struct( ...
                            'name', info.name, 'rows', rows, 'cols', channels, ...
                            'size', sprintf('%d x %d (struct)', rows, channels)); %#ok<AGROW>
                    end
                end
            end
        end

        function vectors = collectWorkspaceVectors(~)
            workspace = evalin('base', 'whos');
            vectors = {};
            numericClasses = {'double','single','int8','int16','int32', ...
                'int64','uint8','uint16','uint32','uint64'};
            for index = 1:numel(workspace)
                info = workspace(index);
                if info.global || ~ismember(info.class, numericClasses) || ...
                        numel(info.size) ~= 2 || ...
                        ~(info.size(1) == 1 || info.size(2) == 1)
                    continue;
                end
                lengthValue = max(info.size);
                if lengthValue >= 3
                    vectors{end + 1} = struct( ...
                        'name', info.name, 'length', lengthValue); %#ok<AGROW>
                end
            end
        end

        function name = suggestName(~, existingNames, baseName)
            name = baseName;
            suffix = 1;
            while any(strcmp(existingNames, name))
                name = sprintf('%s_%d', baseName, suffix);
                suffix = suffix + 1;
            end
        end

        function bytes = estimatePlotBytes(~, nSamples, nChannels)
            bytes = double(nSamples) * double(nChannels) * 8;
        end

        function sendResponse(app, responseType, payload)
            if app.IsClosed || ~app.UiReady
                return;
            end
            app.ResponseCounter = app.ResponseCounter + 1;
            response = struct();
            response.response = responseType;
            response.payload = payload;
            response.source = 'matlab';
            response.timestamp = app.ResponseCounter;
            app.HTMLComponent.Data = response;
        end
    end

    methods (Access = public)
        function setInputData(app, inputData)
            % SETINPUTDATA Validate and load numeric or struct input.
            %
            %   Numeric vectors become one row. Matrix rows are preserved.
            [valid, normalized, message] = app.Validator.normalize( ...
                inputData, [], 'inputData');
            if ~valid
                error('SavGol:InvalidInput', '%s', message);
            end
            loadNormalizedData(app, normalized);
            deliverDataLoaded(app, buildDataLoadedPayload(app));
        end

        function output = getData(app)
            % GETDATA Return the current result and metadata struct.
            if isempty(app.ProcessedData)
                output = struct('data', [], 'spectra', [], ...
                    'wavelength', [], 'wavelengths', [], ...
                    'varName', app.LoadedVarName, 'metadata', struct(), ...
                    'isCurrent', false);
                if app.DataLoaded
                    output.wavelength = app.InputData.wavelength;
                    output.wavelengths = app.InputData.wavelength;
                end
            else
                output = app.ProcessedData;
                output.isCurrent = app.ResultIsCurrent;
            end
        end

    end
end
