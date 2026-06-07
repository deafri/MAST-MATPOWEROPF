function hourly_OPF_LMP (cfgFile,solutionCsv,busXlsx)
% ================================================================
%  hourly_OPF_LMP.m
%  ----------------
%  • Builds an MPC for every hour in MAST’s solution.csv
%  • Solves an AC-OPF (with renewables kept in the case)
%  • Collects Λ_P (LMP) duals for every bus and every hour
%  • Saves the result as a tidy table  →  LMP_hourly.csv
% ================================================================



% ----------------------------------------------------------------

% ---------- how many hours? -------------------------------------
[tDisp, ~]  = read_mast_dispatch(solutionCsv);
Nt          = height(tDisp);               % number of rows = # hours

% ---------- bus labels & count (grab once) ----------------------
mpc0        = build_mpc_from_excel_keepRE(busXlsx);
Nb          = size(mpc0.bus, 1);
busNames    = string(mpc0.bus_name).';     % 1 × Nb row vector

% ---------- storage for LMPs ------------------------------------
LMP         = NaN(Nt, Nb);                 % each row = one hour

% ---------- MATPOWER options (silent) ---------------------------
mpopt = mpoption('verbose', 0, 'out.all', 0);

% ---------- main loop -------------------------------------------
fprintf('Running OPF for %d hourly intervals …\n', Nt);
tic
for h = 1:Nt
    % 1) build case (keeps renewables)
    mpc  = run_single_opf_keepRE(cfgFile, solutionCsv, busXlsx, h);

    % 2) solve OPF
    results = runopf(mpc, mpopt);
    if ~results.success
        warning('Hour %d: OPF did not converge – Λ_P set to NaN.', h);
        continue
    end

    % 3) grab Λ_P ($/MWh)  –  col 14 in results.bus (DEFINE_CONSTANTS)
    define_constants;           % brings LAM_P into scope
    LMP(h, :) = results.bus(:, LAM_P).';   % 1 × Nb row
end
fprintf('Done in %.1f s\n', toc);

% ---------- assemble & save tidy table --------------------------
Hour      = (0:Nt-1).';                   
LMP_table = array2table([Hour, LMP], ...
                'VariableNames', ['Hour', busNames]);

% Save into subfolder "HourlyLMP"
outDir  = 'HourlyLMP';
outFile = fullfile(outDir, 'LMP_hourly.csv');

% (Optional safety) ensure folder exists
if ~exist(outDir, 'dir'); mkdir(outDir); end

writetable(LMP_table, outFile);
disp(LMP_table)
fprintf('\nLMPs written to  %s  (%d×%d)\n', outFile, Nt, Nb+1);


end
