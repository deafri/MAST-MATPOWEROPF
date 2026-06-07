function base = hourly_OPF_LMP(cfgFile, solutionCsv, busXlsx)
% ================================================================
%  hourly_OPF_LMP.m
%  ----------------
%  • Builds an MPC for every hour in MAST’s solution.csv
%  • Solves an AC-OPF (with renewables kept in the case)
%  • Collects Λ_P (LMP) duals for every bus and every hour
%  • Collects baseline PD for every bus and every hour
%  • Saves both as tidy tables:
%       -> HourlyLMP/LMP_hourly.csv
%       -> HourlyLMP/pd_hourly.csv
%  • Returns baseline data directly as a struct:
%       base.busNames
%       base.LMP
%       base.PD_base
%       base.Hour
% ================================================================

%% ---------- Hour Count -------------------------------------
[tDisp, ~]  = read_mast_dispatch(solutionCsv);
Nt          = height(tDisp);               % number of rows = # hours

%% ---------- bus labels & count ------------------------------
mpc0        = build_mpc_from_excel_keepRE(busXlsx);
Nb          = size(mpc0.bus, 1);
busNames    = string(mpc0.bus_name).';     % 1 × Nb row vector

%% ---------- storage for outputs -----------------------------
LMP         = NaN(Nt, Nb);                 % each row = one hour
PD_hourly   = NaN(Nt, Nb);                 % each row = one hour

%% ---------- MATPOWER options -------------------------------
mpopt = mpoption('verbose', 0, 'out.all', 0);

%% ---------- constants --------------------------------------
define_constants;   % brings PD, LAM_P, etc. into scope

%% ---------- main loop --------------------------------------
fprintf('Running OPF for %d hourly intervals ...\n', Nt);
tic
for h = 1:Nt
    % 1) Build hourly case (keeps renewables)
    mpc = run_single_opf_keepRE(cfgFile, solutionCsv, busXlsx, h);

    % 2) Store the baseline PD used in this hourly case
    PD_hourly(h, :) = mpc.bus(:, PD).';

    % 3) Solve OPF
    results = runopf(mpc, mpopt);
    if ~results.success
        warning('Hour %d: OPF did not converge - LMP set to NaN.', h);
        continue
    end

    % 4) Store LMP ($/MWh)
    LMP(h, :) = results.bus(:, LAM_P).';
end
fprintf('Done in %.1f s\n', toc);

%% ---------- assemble tidy tables ----------------------------
Hour = (0:Nt-1).';

LMP_table = array2table([Hour, LMP], ...
    'VariableNames', ['Hour', cellstr(busNames)]);

PD_table = array2table([Hour, PD_hourly], ...
    'VariableNames', ['Hour', cellstr(busNames)]);

%% ---------- save into HourlyLMP subfolder -------------------
scriptDir = fileparts(mfilename('fullpath'));
outDir    = fullfile(scriptDir, 'HourlyLMP');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

lmpFile = fullfile(outDir, 'LMP_hourly.csv');
pdFile  = fullfile(outDir, 'pd_hourly.csv');

writetable(LMP_table, lmpFile);
writetable(PD_table, pdFile);

fprintf('\nLMPs written to %s  (%d x %d)\n', lmpFile, Nt, Nb+1);
fprintf('PD matrix written to %s  (%d x %d)\n', pdFile, Nt, Nb+1);

%% ---------- return baseline data directly -------------------
base.busNames = cellstr(busNames);
base.LMP      = LMP;
base.PD_base  = PD_hourly;
base.Hour     = Hour;

end