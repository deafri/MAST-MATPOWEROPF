function out = plot_mast_generation_stack(solutionCsv)
% ================================================================
% plot_mast_generation_stack.m
%
% PURPOSE:
%   Reproduce a MAST-style generation stack plot from a solution file.
%
% FIXES:
%   1) Utility storage discharge is included as positive supply
%   2) Utility storage charge is shown below zero
%   3) Demand is reconstructed from the full balance equation
%   4) Legend/colors are matched to the MAST screenshot
%   5) Time axis is shifted by 12 hours for correct visual alignment
% ================================================================

clc; close all;

if nargin < 1 || isempty(solutionCsv)
    solutionCsv = 'VPP1.csv';
end

%% Read solution
[tDisp, ~] = read_mast_dispatch(solutionCsv);
vars = tDisp.Properties.VariableNames;
Hour = hours(tDisp.Time);
Hour = Hour(:);
Nt = numel(Hour);

%% Extract generation columns
pgMask = endsWith(vars, '_Pg', 'IgnoreCase', true);
if ~any(pgMask)
    error('No *_Pg columns found in %s', solutionCsv);
end
PgTbl = array2table(tDisp{:, pgMask}, 'VariableNames', vars(pgMask));

%% Group technologies
BlackCoal    = sum_matching(PgTbl, {'blackcoal','black_coal','coal'});
BrownCoal    = sum_matching(PgTbl, {'browncoal','brown_coal'});
Hydro        = sum_matching(PgTbl, {'hydro'});
Wind         = sum_matching(PgTbl, {'wind'});
UtilitySolar = sum_matching(PgTbl, {'utilitysolar','utility_solar','utilsolar','solar','pv','cst'});
Gas          = sum_matching(PgTbl, {'gas','ocgt','ccgt'});

% fallback if coal is only named generically
if all(BlackCoal == 0) && all(BrownCoal == 0)
    BlackCoal = sum_matching(PgTbl, {'coal'});
end

%% Storage
chrgMask = endsWith(vars, '_P_chrg', 'IgnoreCase', true);
disMask  = endsWith(vars, '_P_dischrg', 'IgnoreCase', true);

if any(chrgMask)
    Pch = sum(tDisp{:, chrgMask}, 2);   % charging
else
    Pch = zeros(Nt,1);
end

if any(disMask)
    Pdis = sum(tDisp{:, disMask}, 2);   % discharging
else
    Pdis = zeros(Nt,1);
end

% Plot convention
UtilityStorage_discharge = Pdis;   % positive stack contribution
UtilityStorage_charge    = -Pch;   % negative area

%% Unserved demand
usdMask = contains(lower(vars), 'unserved');
if any(usdMask)
    UnservedDemand = sum(tDisp{:, usdMask}, 2);
else
    UnservedDemand = zeros(Nt,1);
end

%% Positive stack
stackData = [ ...
    BlackCoal, ...
    BrownCoal, ...
    Hydro, ...
    Wind, ...
    UtilitySolar, ...
    UtilityStorage_discharge, ...
    Gas, ...
    UnservedDemand];

stackNames = { ...
    'BlackCoal', ...
    'BrownCoal', ...
    'Hydro', ...
    'Wind', ...
    'UtilitySolar', ...
    'UtilityStorage', ...
    'Gas', ...
    'UnservedDemand'};

%% System demand from full balance
% generation + discharge + unserved = demand + charge
% therefore:
SystemDemand = sum(stackData, 2) + UtilityStorage_charge;

%% Colours
C.BlackCoal      = [0.00 0.00 0.00];
C.BrownCoal      = [0.70 0.25 0.20];
C.Hydro          = [0.90 0.97 0.99];
C.Wind           = [0.00 0.60 0.00];
C.UtilitySolar   = [1.00 0.68 0.00];
C.UtilityStorage = [0.55 0.00 0.55];
C.Gas            = [0.20 0.85 0.95];
C.UnservedDemand = [0.60 0.60 0.60];
C.SystemDemand   = [0.00 0.10 1.00];

%% Plot
figure('Name','MAST Generation Stack','NumberTitle','off');
hold on;

% Positive supply stack
hArea = area(Hour, stackData, 'LineStyle', 'none');
for k = 1:numel(hArea)
    hArea(k).EdgeColor = 'none';
end

hArea(1).FaceColor = C.BlackCoal;
hArea(2).FaceColor = C.BrownCoal;
hArea(3).FaceColor = C.Hydro;
hArea(4).FaceColor = C.Wind;
hArea(5).FaceColor = C.UtilitySolar;
hArea(6).FaceColor = C.UtilityStorage; % discharge above zero
hArea(7).FaceColor = C.Gas;
hArea(8).FaceColor = C.UnservedDemand;

% Charging below zero
hCharge = area(Hour, UtilityStorage_charge, 'LineStyle', 'none');
hCharge.FaceColor = C.UtilityStorage;
hCharge.EdgeColor = 'none';
hCharge.Annotation.LegendInformation.IconDisplayStyle = 'off';

% Demand line
hDemand = plot(Hour, SystemDemand, 'Color', C.SystemDemand, 'LineWidth', 2);

% Zero line
hZero = yline(0, 'k-');
hZero.Annotation.LegendInformation.IconDisplayStyle = 'off';

grid on;

% ----- Time-of-day x-axis with 12-hour offset -----
tickStep = 6;
xt = 0:tickStep:max(Hour);
xticks(xt);
xticklabels(compose('%02d00', mod(xt+12,24)));
xlabel('Time of Day');

% ----- Optional day separators -----
dayBreaks = 24:24:max(Hour);
for k = 1:numel(dayBreaks)
    xline(dayBreaks(k), ':', 'Color', [0.7 0.7 0.7], ...
        'HandleVisibility', 'off');
end

ylabel('Power (MW)');
title(sprintf('System Generation Stack: %s', solutionCsv), 'Interpreter', 'none');

legend([hArea(:); hDemand], ...
       [stackNames, {'SystemDemand'}], ...
       'Location', 'eastoutside');

%% Balance check
netSupply = BlackCoal + BrownCoal + Hydro + Wind + UtilitySolar + Pdis + Gas + UnservedDemand - Pch;
balanceError = netSupply - SystemDemand;

fprintf('\n====================================================\n');
fprintf('Balance check for: %s\n', solutionCsv);
fprintf('Max abs balance error = %.6f MW\n', max(abs(balanceError)));
fprintf('====================================================\n');

%% Output
out.Hour = Hour;
out.BlackCoal = BlackCoal;
out.BrownCoal = BrownCoal;
out.Hydro = Hydro;
out.Wind = Wind;
out.UtilitySolar = UtilitySolar;
out.UtilityStorage_discharge = UtilityStorage_discharge;
out.UtilityStorage_charge = UtilityStorage_charge;
out.Gas = Gas;
out.UnservedDemand = UnservedDemand;
out.Pch = Pch;
out.Pdis = Pdis;
out.SystemDemand = SystemDemand;
out.BalanceError = balanceError;

end

%% Helper
function y = sum_matching(T, keywords)
vars = T.Properties.VariableNames;
pick = false(1, numel(vars));

for i = 1:numel(vars)
    name = lower(vars{i});
    for k = 1:numel(keywords)
        if contains(name, lower(keywords{k}))
            pick(i) = true;
            break;
        end
    end
end

if any(pick)
    y = sum(T{:, pick}, 2);
else
    y = zeros(height(T),1);
end
end