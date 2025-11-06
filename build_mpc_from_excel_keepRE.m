function mpc = build_mpc_from_excel_keepRE(xlsfile)
% BUILD_MPC_FROM_EXCEL_KEEPRE  Build a MATPOWER case (bus + branch + gen)
%                              without removing renewable rows.
%
%   mpc = build_mpc_from_excel_keepRE('5bus_New.xlsx')
%
%   
%     “Generator Data” sheet (wind, solar, hydro, storage …  all stay).
%   – Still expands PMAX/PMIN and cost C₀/start-up/shut-down by
%     “Number of Units”.
%   – Leaves mpc.baseMVA = 100 

%% 0)  INITIAL SET-UP

mpc.version = '2';
mpc.baseMVA = 100;

opts    = {'VariableNamingRule','preserve'};
bus_tbl = readtable(xlsfile, 'Sheet','Bus Data',    opts{:});
br_tbl  = readtable(xlsfile, 'Sheet','Branch Data', opts{:});
gen_tbl = readtable(xlsfile, 'Sheet','Generator Data', opts{:});


%% 1)  BUS SECTION  

norm = @(s) lower(strtrim(string(s)));
busNamesRaw = bus_tbl.('Bus Name');
busNames    = norm(busNamesRaw);
Nb          = numel(busNames);
bus_i       = (1:Nb).';

% ---------- bus-type -------------------------------------------------
bus_type = ones(Nb,1);        % default PQ
if ismember('Bus Type',bus_tbl.Properties.VariableNames)
    raw = bus_tbl.('Bus Type');
    for k = 1:Nb
        val = raw(k);
        if isnumeric(val), t = val;
        else,              t = lower(strtrim(string(val)));
        end
        if isnumeric(val)
            bus_type(k) = val;
        elseif t == "slack"
            bus_type(k) = 3;
        elseif t == "pv"
            bus_type(k) = 2;
        end
    end
end
if ~any(bus_type==3), bus_type(find(bus_type==2,1,'first')) = 3; end

% ---------- demand ---------------------------------------------------
Pd = zeros(Nb,1);  Qd = zeros(Nb,1);
if ismember('Real Demand (MW)',bus_tbl.Properties.VariableNames)
    Pd = bus_tbl.('Real Demand (MW)');
end
if ismember('Reactive Demand (MVAr)',bus_tbl.Properties.VariableNames)
    Qd = bus_tbl.('Reactive Demand (MVAr)');
elseif ismember('Power Factor',bus_tbl.Properties.VariableNames)
    pf = bus_tbl.('Power Factor');  pf(pf<=0|pf>1)=1;
    Qd = Pd .* tan(acos(pf));
end
Pd = Pd(:);  Qd = Qd(:);

% ---------- voltage + misc -------------------------------------------
Vm   = ones(Nb,1);   Va   = zeros(Nb,1);
Vmin = 0.9*ones(Nb,1);  Vmax = 1.1*ones(Nb,1);
if ismember('Minimum Voltage (pu)',bus_tbl.Properties.VariableNames)
    Vmin = bus_tbl.('Minimum Voltage (pu)');
end
if ismember('Maximum Voltage (pu)',bus_tbl.Properties.VariableNames)
    Vmax = bus_tbl.('Maximum Voltage (pu)');
end
Gs   = zeros(Nb,1);   Bs   = zeros(Nb,1);
area = ones(Nb,1);    zone = ones(Nb,1);
if ismember('Base_kV',bus_tbl.Properties.VariableNames)
    base_kV = bus_tbl.('Base_kV');
else
    base_kV = 230*ones(Nb,1);
end

% ---------- assemble bus matrix --------------------------------------
mpc.bus = [ bus_i bus_type Pd Qd Gs Bs area Vm Va base_kV zone Vmax Vmin ];
mpc.bus_name = cellstr(busNamesRaw);
mpc.name2idx = containers.Map(busNames,1:Nb);

%% 2)  BRANCH SECTION  

Nbr  = height(br_tbl);
fbus = zeros(Nbr,1); tbus = zeros(Nbr,1);
for k = 1:Nbr
    fbus(k) = mpc.name2idx(norm(br_tbl.('End 1 Bus Name'){k}));
    tbus(k) = mpc.name2idx(norm(br_tbl.('End 2 Bus Name'){k}));
end
r   = br_tbl.('Resistance (pu)');
x   = br_tbl.('Reactance (pu)');
b   = ismember('Susceptance (pu)',br_tbl.Properties.VariableNames) ...
        .* br_tbl.('Susceptance (pu)');
rateA = zeros(Nbr,1);
if ismember('Thermal Limit (MVA)',br_tbl.Properties.VariableNames)
    rateA = br_tbl.('Thermal Limit (MVA)');
end
rateB = rateA;  rateC = rateA;
tap   = ones(Nbr,1);
if ismember('Tap Ratio (pu)',br_tbl.Properties.VariableNames)
    tap(~isnan(br_tbl.('Tap Ratio (pu)'))) = br_tbl.('Tap Ratio (pu)');
end
shift = zeros(Nbr,1);
if ismember('Phase Shift (deg)',br_tbl.Properties.VariableNames)
    shift = br_tbl.('Phase Shift (deg)');
end
status = ones(Nbr,1);
if ismember('In Service',br_tbl.Properties.VariableNames)
    raw = br_tbl.('In Service');
    if isnumeric(raw)
        status = double(raw);
    else
        status = double(strcmpi(raw,'yes') | strcmpi(raw,'y'));
    end
end
angmax = 360*ones(Nbr,1);
if ismember('Maximum Angle Limit (degree)',br_tbl.Properties.VariableNames)
    angmax = br_tbl.('Maximum Angle Limit (degree)');
end
angmin = -angmax;

mpc.branch = [fbus tbus r x b rateA rateB rateC tap shift status angmin angmax];


%% 3)  GENERATOR SECTION 

Ng = height(gen_tbl);
genBus = zeros(Ng,1);
for k = 1:Ng
    genBus(k) = mpc.name2idx(norm(gen_tbl.('Location Bus'){k}));
end

% number-of-units ------------------------------------------------------
if ~ismember('Number of Units', gen_tbl.Properties.VariableNames)
    error('"Number of Units" column missing in Generator Data sheet.');
end
nUnits = double(gen_tbl.('Number of Units'));
mpc.nUnits = nUnits;

% limits & initial dispatch -------------------------------------------
Pmax = gen_tbl.('Maximum Real Power (MW)');
Pmin = gen_tbl.('Minimum Real Power (MW)');
Qmax = gen_tbl.('Maximum Reactive Power (MVar)');
Qmin = gen_tbl.('Minimum Reactive Power (MVar)');

define_constants
Pg0 = Pmin;  Qg0 = max(Qmin,0);
Vg  = ones(Ng,1);
stat = ones(Ng,1);
mBase = mpc.baseMVA * ones(Ng,1);
zero8 = zeros(Ng,8);  ramp4 = zeros(Ng,4);  apf = zeros(Ng,1);

mpc.gen = [ genBus Pg0 Qg0 Qmax Qmin Vg mBase stat Pmax Pmin ...
            zero8 ramp4 apf ];
mpc.gen_name = gen_tbl.('Generator Name');
mpc.gen_idx  = containers.Map(mpc.gen_name,1:Ng);

% gencost --------------------------------------------------------------
startup  = gen_tbl.('Start up Cost ($)');
shutdown = gen_tbl.('Shut down Cost ($)');
c1       = gen_tbl.('Variable Cost ($/MW)');
c0       = gen_tbl.('Fix Cost ($)');
c2       = zeros(Ng,1);
mpc.gencost = [2*ones(Ng,1) startup shutdown 3*ones(Ng,1) c2 c1 c0];

% expand by nUnits -----------------------------------------------------
colsScale = [ PG QG PMAX PMIN QMAX QMIN ];
mpc.gen(:,colsScale) = mpc.gen(:,colsScale) .* nUnits;

mpc.gencost(:,2) = mpc.gencost(:,2) .* nUnits;   % startup
mpc.gencost(:,3) = mpc.gencost(:,3) .* nUnits;   % shutdown
mpc.gencost(:,7) = mpc.gencost(:,7) .* nUnits;   % C0

fprintf('[DEBUG]  Applied unit-multipliers : %s\n', mat2str(nUnits.'));
fprintf('         PMAX totals now = %s MW\n', mat2str(mpc.gen(:,PMAX).'));


end
