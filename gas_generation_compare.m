function out = gas_generation_compare(solutionFile1, solutionFile2)
% ================================================================
% gas_generation_compare.m
% ------------------------------------------------
% PURPOSE:
%   Compare gas generation from two different MAST solution files.
%
% USAGE:
%   out = gas_generation_compare('solution1.csv', 'solution2.csv')
%
% INPUTS:
%   solutionFile1   - first MAST solution file
%   solutionFile2   - second MAST solution file
%
% OUTPUT:
%   out structure containing:
%       out.case1
%       out.case2
%       out.delta
%
% NOTES:
%   - Uses read_mast_dispatch(solutionCsv)
%   - Looks for columns that contain "gas" and end with "_Pg"
%   - Assumes 1-hour timestep
% ================================================================

clc; close all;

if nargin < 2
    error('Usage: gas_generation_compare(''solution1.csv'',''solution2.csv'')');
end

%% Extract gas generation from both files ------------------------
case1 = extract_one_case(solutionFile1);
case2 = extract_one_case(solutionFile2);

%% Consistency checks --------------------------------------------
if numel(case1.Hour) ~= numel(case2.Hour)
    error('The two solution files do not have the same number of hours.');
end

if any(case1.Hour ~= case2.Hour)
    warning('Hour vectors do not exactly match. Proceeding with case1 hour axis.');
end

Hour = case1.Hour(:);

%% Differences ---------------------------------------------------
deltaHourly_MW = case2.GasHourly_MW - case1.GasHourly_MW;
deltaTotal_MWh = case2.TotalGas_MWh - case1.TotalGas_MWh;
deltaPeak_MW   = case2.PeakGas_MW   - case1.PeakGas_MW;
deltaAvg_MW    = case2.AvgGas_MW    - case1.AvgGas_MW;

%% Print summary -------------------------------------------------
fprintf('\n============================================================\n');
fprintf('Gas generation comparison summary\n');
fprintf('============================================================\n');

fprintf('Case 1 file                : %s\n', solutionFile1);
fprintf('Case 2 file                : %s\n', solutionFile2);

fprintf('\nCase 1:\n');
fprintf('  Total Gas Generation     : %.4f MWh\n', case1.TotalGas_MWh);
fprintf('  Peak Gas Output          : %.4f MW\n',  case1.PeakGas_MW);
fprintf('  Average Gas Output       : %.4f MW\n',  case1.AvgGas_MW);

fprintf('\nCase 2:\n');
fprintf('  Total Gas Generation     : %.4f MWh\n', case2.TotalGas_MWh);
fprintf('  Peak Gas Output          : %.4f MW\n',  case2.PeakGas_MW);
fprintf('  Average Gas Output       : %.4f MW\n',  case2.AvgGas_MW);

fprintf('\nDifference (Case 2 - Case 1):\n');
fprintf('  Delta Total Gas          : %.4f MWh\n', deltaTotal_MWh);
fprintf('  Delta Peak Gas           : %.4f MW\n',  deltaPeak_MW);
fprintf('  Delta Average Gas        : %.4f MW\n',  deltaAvg_MW);
fprintf('============================================================\n');

%% Save tables ---------------------------------------------------
scriptDir = fileparts(mfilename('fullpath'));

comparisonTable = table( ...
    Hour, ...
    case1.GasHourly_MW, ...
    case2.GasHourly_MW, ...
    deltaHourly_MW, ...
    'VariableNames', {'Hour','Gas_Case1_MW','Gas_Case2_MW','Delta_Case2_minus_Case1_MW'});

summaryTable = table( ...
    string(solutionFile1), ...
    string(solutionFile2), ...
    case1.TotalGas_MWh, ...
    case2.TotalGas_MWh, ...
    deltaTotal_MWh, ...
    case1.PeakGas_MW, ...
    case2.PeakGas_MW, ...
    deltaPeak_MW, ...
    case1.AvgGas_MW, ...
    case2.AvgGas_MW, ...
    deltaAvg_MW, ...
    'VariableNames', { ...
        'Case1_File', ...
        'Case2_File', ...
        'Case1_TotalGas_MWh', ...
        'Case2_TotalGas_MWh', ...
        'Delta_TotalGas_MWh', ...
        'Case1_PeakGas_MW', ...
        'Case2_PeakGas_MW', ...
        'Delta_PeakGas_MW', ...
        'Case1_AvgGas_MW', ...
        'Case2_AvgGas_MW', ...
        'Delta_AvgGas_MW'});

comparisonCsv = fullfile(scriptDir, 'gas_generation_comparison.csv');
summaryCsv    = fullfile(scriptDir, 'gas_generation_comparison_summary.csv');

writetable(comparisonTable, comparisonCsv);
writetable(summaryTable, summaryCsv);

fprintf('Comparison CSV written to:\n  %s\n', comparisonCsv);
fprintf('Summary CSV written to:\n  %s\n', summaryCsv);

%% Plot 1: Hourly gas generation comparison ----------------------
figure('Name','Gas Generation Comparison','NumberTitle','off');
plot(Hour, case1.GasHourly_MW, 'LineWidth', 1.5); hold on;
plot(Hour, case2.GasHourly_MW, 'LineWidth', 1.5);
grid on;
xlabel('Hour');
ylabel('Gas Generation (MW)');
title('Hourly Gas Generation Comparison');
legend(make_legend_label(solutionFile1), make_legend_label(solutionFile2), ...
    'Location','best', 'Interpreter','none');

%% Plot 2: Hourly difference ------------------------------------
figure('Name','Gas Generation Difference','NumberTitle','off');
plot(Hour, deltaHourly_MW, 'LineWidth', 1.5);
yline(0, '--');
grid on;
xlabel('Hour');
ylabel('\Delta Gas Generation (MW)');
title('Hourly Gas Generation Difference (Case 2 - Case 1)');

%% Plot 3: Total / Peak / Average comparison --------------------
figure('Name','Gas Summary Comparison','NumberTitle','off');

subplot(3,1,1)
bar([case1.TotalGas_MWh, case2.TotalGas_MWh]);
grid on;
ylabel('MWh');
title('Total Gas Generation');
set(gca, 'XTickLabel', {'Cases'});
legend(make_legend_label(solutionFile1), make_legend_label(solutionFile2), ...
    'Location','best', 'Interpreter','none');

subplot(3,1,2)
bar([case1.PeakGas_MW, case2.PeakGas_MW]);
grid on;
ylabel('MW');
title('Peak Gas Output');
set(gca, 'XTickLabel', {'Cases'});
legend(make_legend_label(solutionFile1), make_legend_label(solutionFile2), ...
    'Location','best', 'Interpreter','none');

subplot(3,1,3)
bar([case1.AvgGas_MW, case2.AvgGas_MW]);
grid on;
ylabel('MW');
title('Average Gas Output');
set(gca, 'XTickLabel', {'Cases'});
legend(make_legend_label(solutionFile1), make_legend_label(solutionFile2), ...
    'Location','best', 'Interpreter','none');

%% Pack outputs --------------------------------------------------
out.case1 = case1;
out.case2 = case2;
out.delta.Hour = Hour;
out.delta.Hourly_MW = deltaHourly_MW;
out.delta.Total_MWh = deltaTotal_MWh;
out.delta.Peak_MW   = deltaPeak_MW;
out.delta.Avg_MW    = deltaAvg_MW;

end

%% =======================================================================
% HELPER FUNCTIONS
% =======================================================================

function gas = extract_one_case(solutionCsv)
    [tDisp, ~] = read_mast_dispatch(solutionCsv);
    vars = tDisp.Properties.VariableNames;

    isPgCol  = endsWith(vars, '_Pg', 'IgnoreCase', true);
    isGasCol = contains(lower(vars), 'gas');

    gasMask = isPgCol & isGasCol;

    if ~any(gasMask)
        error('No gas generation columns found in file: %s', solutionCsv);
    end

    GasMat = tDisp{:, gasMask};
    GasHourly_MW = sum(GasMat, 2);

    Hour = hours(tDisp.Time);
    Hour = Hour(:);

    gas.FileName      = solutionCsv;
    gas.GasColumns    = vars(gasMask);
    gas.Hour          = Hour;
    gas.GasHourly_MW  = GasHourly_MW;
    gas.TotalGas_MWh  = sum(GasHourly_MW);
    gas.PeakGas_MW    = max(GasHourly_MW);
    gas.AvgGas_MW     = mean(GasHourly_MW);
end

function label = make_legend_label(filePath)
    [~, name, ext] = fileparts(filePath);
    label = [name, ext];
end