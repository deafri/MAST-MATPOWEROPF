% WHOLESALE_PROSUMER_LP_DEMO.m


%% 0)  House-keeping -------------------------------------------------------
clear; clc; close all;

%% 1)  INPUT DATA  ---------------------------------------------------------
% Horizon & clock
T = 48;                                      % 2 days, hourly
t0 = datetime(2025,1,1);
t  = t0 + hours(0:T-1);

% ---- Load profile [MW] (residential-ish: morning & evening peaks)
% Base ~0.6 kW, peak ~2.5 kW  -> convert kW to MW (kW/1000)
kW_base = 0.6 + 0.4*sin(2*pi*(hour(t))/24 - pi/2).^2;    % mild daily shape
kW_peaks = 2.0*(hour(t)>=18 & hour(t)<22) + 1.0*(hour(t)>=7 & hour(t)<9);
L = (kW_base + kW_peaks)/1000;               % MW

% ---- PV profile [MW] (bell around solar noon, zero at night)
pv_kw_peak = 4.0;                             % 4 kW PV system
pv_shape = max(0, cos((hour(t)-12)*pi/12)).^1.6;  % midday bump
PV = (pv_kw_peak * pv_shape)/1000;            % MW

% ---- Wholesale price [$/MWh] (TOU-like with a few spikes)
price = 60 + 20*(hour(t)>=7 & hour(t)<17) + 80*(hour(t)>=17 & hour(t)<21);
price(10) = 300;      % a morning spike
price(35) = 450;      % an evening spike day 2

% ---- Battery (Powerwall-like)
E_max = 13.5/1000;     % MWh (13.5 kWh)
P_max = 5/1000;        % MW  (5 kW)
eta_c = 0.95;          % charge efficiency
eta_d = 0.95;          % discharge efficiency
E0    = 0.5*E_max;     % initial SoC (50%)
enforce_cycle_neutral = true;  % enforce E(T) = E0

%% 2)  BUILD THE LP --------------------------------------------------------
% Decision vector (length 5T):
% x = [ Pc(1..T) ; Pd(1..T) ; Pimp(1..T) ; Pexp(1..T) ; E(1..T) ]
[A, b, Aeq, beq, lb, ub, f] = buildLP(L, PV, price, E_max, P_max, ...
    eta_c, eta_d, E0, enforce_cycle_neutral);

%% 3)  SOLVE ---------------------------------------------------------------
opts = optimoptions('linprog','Algorithm','dual-simplex','Display','none');
[x_opt, cost_opt, exitflag, output] = linprog(f, A, b, Aeq, beq, lb, ub, opts);

%% 4)  POST-PROCESS --------------------------------------------------------
results = postProcess(x_opt, L, PV, price, T, t);

fprintf('\n------ Wholesale prosumer LP (example) ------\n');
fprintf('Objective value  : $%.2f\n', cost_opt);
fprintf('Exit flag / iter : %d / %d\n', exitflag, output.iterations);

% ---- Plots
figure(1); clf;
subplot(3,1,1)
plot(results.Time, results.LoadkW, '-', results.Time, results.PVkW, '--');
ylabel('kW'); grid on; legend('Load','PV','Location','best'); title('Load & PV');

subplot(3,1,2)
plot(results.Time, results.NetGridkW, '-'); grid on;
ylabel('kW'); legend('Import (+) / Export (-)','Location','best'); title('Net Grid Power');

subplot(3,1,3)
yyaxis left;  plot(results.Time, results.E_kWh, '-'); ylabel('Battery SoC [kWh]');
yyaxis right; plot(results.Time, results.Price,  '--'); ylabel('Price [$/MWh]');
grid on; title('Battery SoC and Price');
xlabel('Time');

%% ------------------------------------------------------------------------
% HELPER FUNCTIONS
function [A, b, Aeq, beq, lb, ub, f] = buildLP(L, PV, price, E_max, P_max, ...
                                               eta_c, eta_d, E0, enforce_cycle_neutral)
    % BUILDLP  Assemble matrices for: x = [Pc; Pd; Pimp; Pexp; E]
    % Power balance per hour:
    %   L(t) - PV(t) + Pc(t) - Pd(t) = Pimp(t) - Pexp(t)
    %
    % SoC recursion (dt = 1 h):
    %   E(t) = E(t-1) + eta_c*Pc(t) - (1/eta_d)*Pd(t)
    %   with E(1) = E0 + eta_c*Pc(1) - (1/eta_d)*Pd(1)
    %
    % Bounds:
    %   0 ≤ Pc,Pd ≤ P_max ; 0 ≤ Pimp,Pexp ; 0 ≤ E ≤ E_max

    T = numel(L);
    N = 5*T;

    % Objective: import*price - export*price
    f = zeros(N,1);
    f(2*T+1:3*T) = price(:);   % Pimp
    f(3*T+1:4*T) = -price(:);  % Pexp

    % Variable bounds
    lb = zeros(N,1);
    ub = inf(N,1);
    ub(1:T)       = P_max;   % Pc
    ub(T+1:2*T)   = P_max;   % Pd
    ub(4*T+1:5*T) = E_max;   % E

    % ---------- Equality constraints ----------
    % Power balance for each t
    % [Pc] +1, [Pd] -1, [Pimp] -1, [Pexp] +1, RHS = PV - L  (move terms)
    rows_pb = (1:T)';
    Aeq_pb = sparse(rows_pb,            (1:T),          +1, T, N);           % Pc
    Aeq_pb = Aeq_pb + sparse(rows_pb,   (T+1:2*T),      -1, T, N);           % Pd
    Aeq_pb = Aeq_pb + sparse(rows_pb,   (2*T+1:3*T),    -1, T, N);           % Pimp
    Aeq_pb = Aeq_pb + sparse(rows_pb,   (3*T+1:4*T),    +1, T, N);           % Pexp
    beq_pb = PV(:) - L(:);

    % SoC recursion
    % For t=1:  E1 - eta_c*Pc1 + (1/eta_d)*Pd1 = E0
    Aeq_soc = sparse(T, N);
    beq_soc = zeros(T,1);

    % t = 1 row
    Aeq_soc(1, 4*T+1) = 1;                     % E1
    Aeq_soc(1, 1)     = -eta_c;                % -eta_c*Pc1
    Aeq_soc(1, T+1)   = +1/eta_d;              % +(1/eta_d)*Pd1
    beq_soc(1)        = E0;

    % t = 2..T rows:  E(t) - E(t-1) - eta_c*Pc(t) + (1/eta_d)*Pd(t) = 0
    for tt = 2:T
        Aeq_soc(tt, 4*T+tt)   =  1;            % E(t)
        Aeq_soc(tt, 4*T+tt-1) = -1;            % -E(t-1)
        Aeq_soc(tt, tt)       = -eta_c;        % -eta_c*Pc(t)
        Aeq_soc(tt, T+tt)     = +1/eta_d;      % +(1/eta_d)*Pd(t)
        % RHS stays 0
    end

    % Optional cycle-neutral: E(T) = E0
    if enforce_cycle_neutral
        Aeq_cn = sparse(1, 4*T+T, 1, 1, N);
        beq_cn = E0;
        Aeq = [Aeq_pb; Aeq_soc; Aeq_cn];
        beq = [beq_pb; beq_soc; beq_cn];
    else
        Aeq = [Aeq_pb; Aeq_soc];
        beq = [beq_pb; beq_soc];
    end

    % ---------- Inequalities (none needed here) ----------
    A = []; b = [];

    % (Note: mutual exclusivity of Pc/Pd would require binaries; we keep LP.)
end

function results = postProcess(x, L, PV, price, T, tvec)
    % Unpack
    Pc   = x(1:T);
    Pd   = x(T+1:2*T);
    Pimp = x(2*T+1:3*T);
    Pexp = x(3*T+1:4*T);
    E    = x(4*T+1:5*T);

    % Derived
    NetGrid = Pimp - Pexp;                  % MW (+ import)
    Cost    = sum(Pimp.*price - Pexp.*price);

    % Pretty units for plots
    results = struct();
    results.Time       = tvec(:);
    results.LoadkW     = L(:)*1000;         % MW -> kW
    results.PVkW       = PV(:)*1000;
    results.Pc_kW      = Pc(:)*1000;
    results.Pd_kW      = Pd(:)*1000;
    results.NetGridkW  = NetGrid(:)*1000;
    results.E_kWh      = E(:)*1000;         % MWh -> kWh
    results.Price      = price(:);
    results.TotalCost  = Cost;
end
