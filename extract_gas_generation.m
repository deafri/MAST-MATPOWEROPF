function gas = extract_gas_generation(solutionCsv)
% ================================================================
% extract_gas_generation.m
% ------------------------------------------------
% PURPOSE:
%   Extract the hourly gas generation from a MAST solution file
%   and compute the total gas generation over the horizon.
%
% INPUT:
%   solutionCsv  - path to MAST solution.csv
%
% OUTPUT:
%   gas structure with:
%       gas.Hour
%       gas.GasHourly_MW
%       gas.TotalGas_MWh
%       gas.GasColumns
%
% NOTES:
%   - Uses read_mast_dispatch(solutionCsv)
%   - Works if gas appears in one or more dispatch columns
%   - Assumes 1-hour intervals, so MW summed over time = MWh
% ================================================================

clc;

if nargin < 1 || isempty(solutionCsv)
    solutionCsv = 'solution.csv';
end

%% Read dispatch timetable --------------------------------------
[tDisp, ~] = read_mast_dispatch(solutionCsv);

vars = tDisp.Properties.VariableNames;

% Find gas-related active power columns
% Example expected after read_mast_dispatch:
%   gas_Pg
%   gas1_Pg
%   peaker_gas_Pg
%
% We look for columns that:
%   1) end with _Pg
%   2) contain "gas"
isPgCol  = endsWith(vars, '_Pg', 'IgnoreCase', true);
isGasCol = contains(lower(vars), 'gas');

gasMask = isPgCol & isGasCol;

if ~any(gasMask)
    error('No gas generation columns were found in the solution file.');
end

gasCols = vars(gasMask);

%% Extract hourly gas dispatch ----------------------------------
GasMat = tDisp{:, gasMask};          % [Nt x Ngas]
GasHourly_MW = sum(GasMat, 2);       % total gas generation each hour
Hour = hours(tDisp.Time);            % convert timetable row times to numeric hours

% If timetable starts at 0h duration, Hour may already be 0:Nt-1
Hour = Hour(:);

%% Compute total gas generation ---------------------------------
TotalGas_MWh = sum(GasHourly_MW);    % assumes 1-hour timestep

%% Store outputs ------------------------------------------------
gas.Hour         = Hour;
gas.GasHourly_MW = GasHourly_MW;
gas.TotalGas_MWh = TotalGas_MWh;
gas.GasColumns   = gasCols;

%% Print summary ------------------------------------------------
fprintf('\n====================================================\n');
fprintf('Gas generation extraction summary\n');
fprintf('====================================================\n');
fprintf('Solution file       : %s\n', solutionCsv);
fprintf('Gas columns found   : %d\n', numel(gasCols));
disp(gasCols(:))
fprintf('Total Gas Generation: %.4f MWh\n', TotalGas_MWh);
fprintf('Peak Gas Output     : %.4f MW\n', max(GasHourly_MW));
fprintf('Average Gas Output  : %.4f MW\n', mean(GasHourly_MW));
fprintf('====================================================\n');

%% Save CSV in local script directory ---------------------------
scriptDir = fileparts(mfilename('fullpath'));
outFile = fullfile(scriptDir, 'gas_generation_summary.csv');

T = table(Hour, GasHourly_MW, ...
    'VariableNames', {'Hour','GasGeneration_MW'});

writetable(T, outFile);

fprintf('Hourly gas summary written to:\n  %s\n', outFile);

%% Plot ---------------------------------------------------------
figure('Name','Hourly Gas Generation','NumberTitle','off');
plot(Hour, GasHourly_MW, 'LineWidth', 1.5);
grid on;
xlabel('Hour');
ylabel('Gas Generation (MW)');
title('Hourly Total Gas Generation');

end