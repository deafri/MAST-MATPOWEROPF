function plot_LMP_PD_results()
% ================================================================
% plot_LMP_PD_results.m
% ------------------------------------------------
% Reads:
%   - HourlyLMP/LMP_hourly.csv
%   - HourlyLMP/pd_hourly.csv
%
% Then plots:
%   1) all-bus LMP on one figure
%   2) all-bus PD on one figure
%   3) per-bus LMP subplots
%   4) per-bus PD subplots
% ================================================================

clear; clc; close all;

%% Locate files ---------------------------------------------------
scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, 'HourlyLMP');

lmpFile = fullfile(dataDir, 'LMP_hourly.csv');
pdFile  = fullfile(dataDir, 'pd_hourly.csv');

if ~isfile(lmpFile)
    error('Could not find file: %s', lmpFile);
end
if ~isfile(pdFile)
    error('Could not find file: %s', pdFile);
end

%% Read CSV files -------------------------------------------------
lmpTbl = readtable(lmpFile, 'VariableNamingRule', 'preserve');
pdTbl  = readtable(pdFile,  'VariableNamingRule', 'preserve');

% Check first column
if ~strcmpi(lmpTbl.Properties.VariableNames{1}, 'Hour')
    error('First column of LMP_hourly.csv must be "Hour".');
end
if ~strcmpi(pdTbl.Properties.VariableNames{1}, 'Hour')
    error('First column of pd_hourly.csv must be "Hour".');
end

Hour = lmpTbl{:,1};

busNamesLMP = lmpTbl.Properties.VariableNames(2:end);
busNamesPD  = pdTbl.Properties.VariableNames(2:end);

if numel(busNamesLMP) ~= numel(busNamesPD) || ~all(strcmp(busNamesLMP, busNamesPD))
    error('Bus names in LMP_hourly.csv and pd_hourly.csv do not match.');
end

busNames = busNamesLMP;
LMP = lmpTbl{:,2:end};
PD  = pdTbl{:,2:end};

Nb = numel(busNames);

%% Plot 1: All bus LMP curves ------------------------------------
figure('Name', 'All Bus LMP Profiles', 'NumberTitle', 'off');
plot(Hour, LMP, 'LineWidth', 1.2);
grid on;
xlabel('Hour');
ylabel('LMP ($/MWh)');
title('Hourly LMP at All Buses');
legend(busNames, 'Location', 'bestoutside');

%% Plot 2: All bus PD curves -------------------------------------
figure('Name', 'All Bus PD Profiles', 'NumberTitle', 'off');
plot(Hour, PD, 'LineWidth', 1.2);
grid on;
xlabel('Hour');
ylabel('PD (MW)');
title('Hourly Active Demand at All Buses');
legend(busNames, 'Location', 'bestoutside');

%% Plot 3: Per-bus LMP subplots ----------------------------------
nRows = ceil(sqrt(Nb));
nCols = ceil(Nb / nRows);

figure('Name', 'Per-Bus LMP Subplots', 'NumberTitle', 'off');
for k = 1:Nb
    subplot(nRows, nCols, k);
    plot(Hour, LMP(:,k), 'LineWidth', 1.2);
    grid on;
    title(sprintf('%s', busNames{k}), 'Interpreter', 'none');
    xlabel('Hour');
    ylabel('LMP');
end
sgtitle('Hourly LMP by Bus');

%% Plot 4: Per-bus PD subplots -----------------------------------
figure('Name', 'Per-Bus PD Subplots', 'NumberTitle', 'off');
for k = 1:Nb
    subplot(nRows, nCols, k);
    plot(Hour, PD(:,k), 'LineWidth', 1.2);
    grid on;
    title(sprintf('%s', busNames{k}), 'Interpreter', 'none');
    xlabel('Hour');
    ylabel('PD');
end
sgtitle('Hourly Active Demand by Bus');

%% Optional: Combined subplot per bus ----------------------------
figure('Name', 'Per-Bus LMP and PD Combined', 'NumberTitle', 'off');
for k = 1:Nb
    subplot(nRows, nCols, k);
    yyaxis left
    plot(Hour, LMP(:,k), 'LineWidth', 1.1);
    ylabel('LMP')

    yyaxis right
    plot(Hour, PD(:,k), '--', 'LineWidth', 1.1);
    ylabel('PD')

    grid on;
    title(sprintf('%s', busNames{k}), 'Interpreter', 'none');
    xlabel('Hour');
end
sgtitle('Hourly LMP and PD by Bus');

fprintf('Plots generated successfully for %d buses.\n', Nb);

end