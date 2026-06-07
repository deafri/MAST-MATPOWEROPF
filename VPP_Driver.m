%% VPP_Driver.m
% Amber-style VPP portfolio optimizer driven by OPF LMPs (single-bus connection).
% Focus: VPP optimizer + outputs (no OPF modification here yet).
% -------------------------------------------------------------------------
clear; clc; close all;

%% 1) LOAD LMP DATA -------------------------------------------------------
csvFile = 'LMP_hourly.csv';
[~, busNames, lmpMat] = load_lmp_hourly_from_csv(csvFile);

% ---- User chooses the VPP bus here (by NAME) ----
VPP_BUS = busNames{1};     % e.g. 'BUS_2', 'NSW', etc. Change this line only.
busID   = find(strcmp(busNames, VPP_BUS));
if isempty(busID), error('VPP bus "%s" not found in CSV header.', VPP_BUS); end

priceUSD = lmpMat(:, busID);      % $/MWh
priceC   = 0.1 * priceUSD;        % c/kWh for plotting

T       = numel(priceUSD);
hourIdx = (0:T-1)';   h24 = mod(hourIdx, 24);

%% 2) VPP SETTINGS --------------------------------------------------------
N = 10;                     % number of prosumers in portfolio (edit as needed)

% Export credit rule (Amber-like pass-through often uses some ratio or FiT policy)
% Keep your "self-consumption switch" if you want:
priceHigh = 70;                              % $/MWh
alpha_t   = double(priceUSD < priceHigh);    % 1 if cheap, 0 if high

% Option A peak penalty (set gamma=0 to disable)
gamma = 25;   % try 0, then e.g. 10, 50, 100 (units depend on scale)

%% 3) SYNTHETIC PROSUMER INPUTS ------------------------------------------
% We generate base shapes then scale each prosumer for diversity.

% Base load shape (kW)
kW_base  = 0.6 + 0.4*sin(2*pi*h24/24 - pi/2).^2;
kW_peaks = 2*(h24>=18 & h24<22) + 1*(h24>=7 & h24<9);
LoadBase_kW = kW_base + kW_peaks;

% Base PV shape (kW)
pvPeak   = 4; % kW
pvShape  = max(0, cos((h24-12)*pi/12)).^1.6;
PVBase_kW = pvPeak * pvShape;

% Build N prosumers: each has (Load, PV) = scale * base + noise
Load_kW = zeros(N,T);
PV_kW   = zeros(N,T);

rng(1); % reproducible
for n = 1:N
    loadScale = 0.8 + 0.6*rand();          % 0.8..1.4
    pvScale   = 0.5 + 1.0*rand();          % 0.5..1.5
    noise     = 0.05*randn(T,1);           % small noise

    Load_kW(n,:) = max(0, loadScale*LoadBase_kW(:)' .* (1+noise(:)'));
    PV_kW(n,:)   = max(0, pvScale*PVBase_kW(:)');   % keep PV nonnegative
end

% Convert to MW
L  = Load_kW/1e3;     % [N x T] MW
PV = PV_kW  /1e3;     % [N x T] MW

%% 4) BATTERY PARAMETERS (PER PROSUMER) ----------------------------------
% You can make them heterogeneous too. Keep simple first.
E_max = (10/1e3) * ones(N,1);    % MWh
P_max = ( 5/1e3) * ones(N,1);    % MW
Pg_max = (3/1e3) * ones(N,1);    % MW grid import/export cap

eta_c = 0.95;  eta_d = 0.95;

E0 = 0.5 * E_max;                % start at 50%
cycleNeutral = true;

%% 5) BUILD & SOLVE VPP PORTFOLIO MILP -----------------------------------
[A,b,Aeq,beq,lb,ub,f,intcon,idx] = buildVPP_MILP( ...
    L, PV, priceUSD, alpha_t, ...
    E_max, P_max, Pg_max, eta_c, eta_d, E0, cycleNeutral, ...
    gamma);

opts = optimoptions('intlinprog','Display','final');
[x, objUSD, flag] = intlinprog(f,intcon,A,b,Aeq,beq,lb,ub,opts);

%% 6) POST PROCESS --------------------------------------------------------
res = postProcessVPP(x, idx, L, PV, priceC, hourIdx, N, T);

fprintf('\nVPP bus = "%s" | N=%d | objective = $%.2f | exit flag %d\n', ...
    VPP_BUS, N, objUSD, flag);

%% 7) PLOTS (VPP portfolio summaries) ------------------------------------
figure(1); clf;
subplot(3,1,1)
plot(res.Hour, res.LoadAgg_kW, '-', res.Hour, res.PVAgg_kW, '--');
ylabel('kW'); legend('Agg Load','Agg PV'); grid on;
title(sprintf('VPP (Agg) Load & PV at %s', VPP_BUS));

subplot(3,1,2)
plot(res.Hour, res.NetGridAgg_kW, '-');
ylabel('kW'); grid on;
title('VPP Net Grid Power (Agg)  (+imp / –exp)');

subplot(3,1,3)
yyaxis left;  plot(res.Hour, res.EAgg_kWh, '-'); ylabel('Agg SoC [kWh]');
yyaxis right; plot(res.Hour, res.Price_c_kWh, '--'); ylabel('Price [c/kWh]');
grid on; xlabel('Hour'); title('Agg SoC & LMP');

% Save the key series for later OPF feedback step
% This is what you will feed into "OPF demand modification" later:
Pgrid_MW = res.NetGridAgg_kW/1e3;   %#ok<NASGU>
save('VPP_output.mat','VPP_BUS','Pgrid_MW','res');

%=========================================================================
% Helper functions
%=========================================================================

function [A,b,Aeq,beq,lb,ub,f,intcon,idx] = buildVPP_MILP( ...
    L, PV, price, alpha_t, E_max, P_max, Pg_max, eta_c, eta_d, E0, cycleNeutral, gamma)

% Decision variables per prosumer n and time t:
% Pc(n,t), Pd(n,t), Pimp(n,t), Pexp(n,t), E(n,t), y(n,t)
% plus optional peak variable Ppeak if gamma>0
%
% Stack order:
% [Pc(:); Pd(:); Pimp(:); Pexp(:); E(:); y(:); (Ppeak)]

    [N,T] = size(L);
    NT = N*T;

    idx.Pc   =            (1:NT);
    idx.Pd   =   NT     + (1:NT);
    idx.Pimp = 2*NT     + (1:NT);
    idx.Pexp = 3*NT     + (1:NT);
    idx.E    = 4*NT     + (1:NT);
    idx.y    = 5*NT     + (1:NT);

    havePeak = (gamma > 0);
    if havePeak
        idx.Ppeak = 6*NT + 1;
        nVars = 6*NT + 1;
    else
        nVars = 6*NT;
    end

    % -------- objective --------------------------------------------------
    f = zeros(nVars,1);

    % price is [T x 1], alpha_t is [T x 1]
    % Apply same price signal to all prosumers at this single bus:
    price_rep = repmat(price(:), N, 1);
    alpha_rep = repmat(alpha_t(:), N, 1);

    f(idx.Pimp) =  price_rep;
    f(idx.Pexp) = -alpha_rep .* price_rep;

    if havePeak
        f(idx.Ppeak) = gamma;
    end

    % -------- bounds -----------------------------------------------------
    lb = zeros(nVars,1);
    ub = inf(nVars,1);

    % Pc/Pd bounds (per prosumer)
    ub(idx.Pc)   = repmat(P_max(:), T, 1);  % repeats each prosumer P_max across time
    ub(idx.Pd)   = repmat(P_max(:), T, 1);
    ub(idx.Pimp) = repmat(Pg_max(:), T, 1);
    ub(idx.Pexp) = repmat(Pg_max(:), T, 1);
    ub(idx.E)    = repmat(E_max(:), T, 1);
    ub(idx.y)    = 1;

    % -------- equalities: power balance per (n,t) ------------------------
    % Pc - Pd - Pimp + Pexp = PV - L
    nEqPB = NT;
    rows = (1:nEqPB)';

    Aeq_pb = sparse(rows, idx.Pc,   +1, nEqPB, nVars) + ...
             sparse(rows, idx.Pd,   -1, nEqPB, nVars) + ...
             sparse(rows, idx.Pimp, -1, nEqPB, nVars) + ...
             sparse(rows, idx.Pexp, +1, nEqPB, nVars);

    beq_pb = PV(:) - L(:);

    % -------- equalities: SoC dynamics per prosumer across time ----------
    % For each prosumer n:
    % E(n,1) - eta_c Pc(n,1) + (1/eta_d) Pd(n,1) = E0(n)
    % E(n,t) - E(n,t-1) - eta_c Pc(n,t) + (1/eta_d) Pd(n,t) = 0
    nEqSOC = NT;
    Aeq_soc = sparse(nEqSOC, nVars);
    beq_soc = zeros(nEqSOC,1);

    % Helper to index (n,t) -> linear k
    lin = @(n,t) (t-1)*N + n;  % column-major by time blocks

    for n = 1:N
        % t=1 row
        r = lin(n,1);
        Aeq_soc(r, idx.E(lin(n,1)))  = 1;
        Aeq_soc(r, idx.Pc(lin(n,1))) = -eta_c;
        Aeq_soc(r, idx.Pd(lin(n,1))) =  1/eta_d;
        beq_soc(r) = E0(n);

        for t = 2:T
            r = lin(n,t);
            Aeq_soc(r, idx.E(lin(n,t)))   = 1;
            Aeq_soc(r, idx.E(lin(n,t-1))) = -1;
            Aeq_soc(r, idx.Pc(lin(n,t)))  = -eta_c;
            Aeq_soc(r, idx.Pd(lin(n,t)))  =  1/eta_d;
        end
    end

    % Optional cycle neutral: E(n,T) = E0(n)
    if cycleNeutral
        nEqCN = N;
        Aeq_cn = sparse(nEqCN, nVars);
        beq_cn = E0(:);
        for n = 1:N
            Aeq_cn(n, idx.E(lin(n,T))) = 1;
        end
        Aeq = [Aeq_pb; Aeq_soc; Aeq_cn];
        beq = [beq_pb; beq_soc; beq_cn];
    else
        Aeq = [Aeq_pb; Aeq_soc];
        beq = [beq_pb; beq_soc];
    end

    % -------- inequalities: mutual exclusion Pc/Pd via y -----------------
    % Pc(n,t) <= Pmax(n) * y(n,t)
    % Pd(n,t) <= Pmax(n) * (1 - y(n,t))  => Pd + Pmax*y <= Pmax
    nIneq = 2*NT;
    A = sparse(nIneq, nVars);
    b = zeros(nIneq,1);

    % Pc - Pmax*y <= 0
    for k = 1:NT
        n = mod(k-1,N) + 1; % prosumer index
        A(k, idx.Pc(k)) = 1;
        A(k, idx.y(k))  = -P_max(n);
    end

    % Pd + Pmax*y <= Pmax
    for k = 1:NT
        n = mod(k-1,N) + 1;
        row = NT + k;
        A(row, idx.Pd(k)) = 1;
        A(row, idx.y(k))  =  P_max(n);
        b(row) = P_max(n);
    end

    % -------- peak constraint (Option A) --------------------------------
    % Ppeak >= sum_n Pimp(n,t) for all t
    if havePeak
        nPeakRows = T;
        A_peak = sparse(nPeakRows, nVars);
        b_peak = zeros(nPeakRows,1);

        for t = 1:T
            row = t;
            % subtract sum Pimp so that: -sum(Pimp) + Ppeak >= 0
            % convert to <= form: sum(Pimp) - Ppeak <= 0
            for n = 1:N
                k = (t-1)*N + n;
                A_peak(row, idx.Pimp(k)) = 1;
            end
            A_peak(row, idx.Ppeak) = -1;
        end

        A = [A; A_peak];
        b = [b; b_peak];
    end

    intcon = idx.y;
end

function res = postProcessVPP(x, idx, L, PV, priceC, hourIdx, N, T)
    Pc   = x(idx.Pc);   Pd   = x(idx.Pd);
    Pimp = x(idx.Pimp); Pexp = x(idx.Pexp);
    E    = x(idx.E);

    % reshape back to [N x T]
    Pc   = reshape(Pc,   [N,T]);
    Pd   = reshape(Pd,   [N,T]);
    Pimp = reshape(Pimp, [N,T]);
    Pexp = reshape(Pexp, [N,T]);
    E    = reshape(E,    [N,T]);

    res.Hour = hourIdx;

    res.LoadAgg_kW    = sum(L,1)'  * 1e3;
    res.PVAgg_kW      = sum(PV,1)' * 1e3;
    res.NetGridAgg_kW = sum(Pimp - Pexp, 1)' * 1e3;
    res.EAgg_kWh      = sum(E,1)' * 1e3;

    res.Price_c_kWh   = priceC(:);
end