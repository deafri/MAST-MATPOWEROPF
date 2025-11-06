function mpc = build_mpc_from_excel(xlsfile)
%   BUILD_MPC_FROM_EXCEL  Build *bus-only* MATPOWER case from Excel.
%   mpc = build_mpc_from_excel('5bus_New.xlsx');
%   mpc.bus_name allows to see physical name of  bus


%% 0) Set Up

mpc.version = '2';
mpc.baseMVA = 100;

opts    = {'VariableNamingRule','preserve'};
bus_tbl = readtable(xlsfile,'Sheet','Bus Data',opts{:});

%% 1) Bus Section
assert(ismember('Bus Name',bus_tbl.Properties.VariableNames), ...
       'Column "Bus Name" not found.');
busNames = string(bus_tbl.('Bus Name'));
Nb       = numel(busNames);
bus_i    = (1:Nb).';


% After reading bus_tbl …
normName = @(s) lower(strtrim(string(s)));      

busNamesRaw = bus_tbl.('Bus Name');              % keep original order
busNames    = normName(busNamesRaw);             % normalised keys
Nb          = numel(busNames);
name2idx    = containers.Map(busNames, 1:Nb);    % Lookup 
mpc.bus_name = cellstr(busNamesRaw);

% 2) Bus Type  
bus_type = ones(Nb,1);                       % default PQ
if ismember('Bus Type',bus_tbl.Properties.VariableNames)
    raw = bus_tbl.('Bus Type');
    for k = 1:Nb
        if isnumeric(raw(k)), t = raw(k);
        else, t = lower(strtrim(string(raw(k))));
        end
        if isnumeric(raw(k))
            bus_type(k) = raw(k);
        elseif t=="slack"
            bus_type(k) = 3;
        elseif t=="pv"
            bus_type(k) = 2;
        end
    end
end
if ~any(bus_type==3)                         % Make sure there is a slack
    idx = find(bus_type==2,1,'first');
    if isempty(idx), idx = 1; end
    bus_type(idx) = 3;
end

% 3) PD, QD
if ismember('Real Demand (MW)',bus_tbl.Properties.VariableNames)
    Pd = bus_tbl.('Real Demand (MW)');
else
    Pd = zeros(Nb,1);
end
if ismember('Reactive Demand (MVAr)',bus_tbl.Properties.VariableNames)
    Qd = bus_tbl.('Reactive Demand (MVAr)');
elseif ismember('Power Factor',bus_tbl.Properties.VariableNames)
    pf = bus_tbl.('Power Factor'); pf(pf<=0|pf>1)=1;
    Qd = Pd.*tan(acos(pf));
else
    Qd = zeros(Nb,1);
end
Pd = Pd(:);  Qd = Qd(:);

% 4) Voltage guesses & limits
Vm = ones(Nb,1);   Va = zeros(Nb,1);
Vmin = 0.9*ones(Nb,1); Vmax = 1.1*ones(Nb,1);
if ismember('Minimum Voltage (pu)',bus_tbl.Properties.VariableNames)
    Vmin = bus_tbl.('Minimum Voltage (pu)');
end
if ismember('Maximum Voltage (pu)',bus_tbl.Properties.VariableNames)
    Vmax = bus_tbl.('Maximum Voltage (pu)');
end

% 5) Misc defaults
Gs   = zeros(Nb,1);  Bs = zeros(Nb,1);
area = ones(Nb,1);   zone = ones(Nb,1);
if ismember('Base_kV',bus_tbl.Properties.VariableNames)
    base_kV = bus_tbl.('Base_kV');
else
    base_kV = 230*ones(Nb,1);
end

% Lookup
name2idx = containers.Map(busNames, 1:Nb);   % bus name → row index

% Assembly for block to print for debug
numeric_block = [ ...
    bus_i  bus_type  Pd  Qd  Gs  Bs  area  Vm  Va  base_kV  zone  Vmax  Vmin ];

mpc.bus       = numeric_block;               % numeric matrix for MATPOWER
mpc.bus_name  = cellstr(busNames);         
mpc.name2idx  = name2idx;                  

% Assemble numeric block (13 columns)
numeric_block = [ ...
    bus_i  bus_type  Pd  Qd  Gs  Bs  area  Vm  Va  base_kV  zone  Vmax  Vmin ];

mpc.bus       = numeric_block;                % pure numeric matrix
mpc.bus_name  = cellstr(busNames);            % {'NSW','QLD',…}
mpc.name2idx  = containers.Map(mpc.bus_name,1:Nb);  % name → index lookup

% Demand Traces
if ismember('Demand Trace Name', bus_tbl.Properties.VariableNames)
    mpc.demand_trace_file = bus_tbl.('Demand Trace Name');   % cell Nb×1
else
    mpc.demand_trace_file = repmat({''}, Nb, 1);              % For blanks
end

if ismember('Demand Trace Weightage', bus_tbl.Properties.VariableNames)
    mpc.demand_trace_weight = bus_tbl.('Demand Trace Weightage');  % Nb×1
else
    mpc.demand_trace_weight = ones(Nb,1);                          % Set default weight to 1 unless specified in bus file
end

% 4) Quick print ----------------------------------------------------------
hdr = {'BUS_I','BUS_TYPE','PD','QD','GS','BS','BUS_AREA', ...
       'VM','VA','BASE_KV','ZONE','VMAX','VMIN'};

Tbus = array2table(mpc.bus,'VariableNames',hdr);
if isfield(mpc,'demand_trace_file')
    Tbus.TraceFile  = string(mpc.demand_trace_file);     % filenames
    Tbus.Multiplier = mpc.demand_trace_weight;           % weightages
end

fprintf('\n--- BUS MATRIX (%d x 13) + demand info ---\n', Nb);
disp(Tbus);

%% ========================== BRANCH SECTION =============================
branch_tbl = readtable(xlsfile,'Sheet','Branch Data',opts{:});
Nbr        = height(branch_tbl);

for k = 1:Nbr
    n1 = normName(branch_tbl.('End 1 Bus Name'){k});
    n2 = normName(branch_tbl.('End 2 Bus Name'){k});
    if ~isKey(name2idx,n1) || ~isKey(name2idx,n2)
        error('Branch row %d has unknown bus "%s" or "%s".', ...
              k, branch_tbl.('End 1 Bus Name'){k}, branch_tbl.('End 2 Bus Name'){k});
    end
    fbus(k) = name2idx(n1);
    tbus(k) = name2idx(n2);
end


% ---- 1) end-bus names → numeric IDs  -----------------------------------
fbus = zeros(Nbr,1);
tbus = zeros(Nbr,1);
bad  = {};                                 % collect unknown names

for k = 1:Nbr
    n1_raw = branch_tbl.('End 1 Bus Name'){k};
    n2_raw = branch_tbl.('End 2 Bus Name'){k};
    n1     = lower(strtrim(string(n1_raw)));    
    n2     = lower(strtrim(string(n2_raw)));

    if isKey(name2idx,n1)
        fbus(k) = name2idx(n1);
    else
        bad{end+1} = char(n1_raw);              
    end

    if isKey(name2idx,n2)  %IDK why there are issues in this part for finding certain parts seem to be fixed for now zzz
        tbus(k) = name2idx(n2);
    else
        bad{end+1} = char(n2_raw);              
    end
end

if ~isempty(bad) % Debuggg
    badList = unique(bad);
    error('Branch sheet contains unknown bus names:\n  %s\nCheck spelling/case/trailing spaces in Bus and Branch sheets.', ...
          strjoin(badList, ', '));
end


% ---- 2) electrical parameters ------------------------------------------
r = branch_tbl.('Resistance (pu)');
x = branch_tbl.('Reactance (pu)');
if ismember('Susceptance (pu)',branch_tbl.Properties.VariableNames)
    b = branch_tbl.('Susceptance (pu)');
else
    b = zeros(Nbr,1);
end

% ---- 3) thermal limits --------------------------------------------------
if ismember('Thermal Limit (MVA)',branch_tbl.Properties.VariableNames)
    rateA = branch_tbl.('Thermal Limit (MVA)');
else
    rateA = zeros(Nbr,1);          
end
rateB = rateA;
rateC = rateA;


tap   = ones(Nbr,1);
shift = zeros(Nbr,1);
if ismember('Tap Ratio (pu)',branch_tbl.Properties.VariableNames)
    tmp = branch_tbl.('Tap Ratio (pu)');
    tap(~isnan(tmp) & tmp~=0) = tmp(~isnan(tmp) & tmp~=0);
end
if ismember('Phase Shift (deg)',branch_tbl.Properties.VariableNames)
    shift = branch_tbl.('Phase Shift (deg)');
end

% ---- 4) status ----------------------------------------------------------
if ismember('In Service',branch_tbl.Properties.VariableNames)
    raw = branch_tbl.('In Service');
    if isnumeric(raw)
        status = double(raw);
    else
        status = double(strcmpi(raw,'yes')|strcmpi(raw,'y')|strcmpi(raw,'1'));
    end
else
    status = ones(Nbr,1);
end

% ---- 5) angle limits ----------------------------------------------------
if ismember('Maximum Angle Limit (degree)',branch_tbl.Properties.VariableNames)
    angmax = branch_tbl.('Maximum Angle Limit (degree)');
else
    angmax = 360*ones(Nbr,1);
end
angmin = -angmax;

% ---- 6) assemble branch matrix (13 cols) --------------------------------
mpc.branch = [ ...
    fbus  tbus  r  x  b  rateA  rateB  rateC  tap  shift  status  angmin  angmax ];

% ---- 7) optional name helpers -------------------------------------------
mpc.branch_name = strcat(branch_tbl.('End 1 Bus Name'),"→", ...
                         branch_tbl.('End 2 Bus Name'));
mpc.branch_idx  = containers.Map(mpc.branch_name, 1:Nbr);

% ---- 98) quick print ------------------------------------------------------
b_hdr = {'F_BUS','T_BUS','BR_R','BR_X','BR_B','RATE_A','RATE_B','RATE_C', ...
         'TAP','SHIFT','BR_STATUS','ANGMIN','ANGMAX'};
fprintf('\n--- BRANCH MATRIX (%d x 13) ---\n', Nbr);
disp(array2table(mpc.branch,'VariableNames',b_hdr));


%% ====================== GENERATOR SECTION =============================
gen_tbl = readtable(xlsfile, 'Sheet','Generator Data', opts{:});
Ng0     = height(gen_tbl);                     % original count

% --- 1) Map Location Bus -> numeric BUS_I ------------------------------
genBus = zeros(Ng0,1);
for k = 1:Ng0
    n = normName(gen_tbl.('Location Bus'){k});
    if ~isKey(name2idx,n)
        error('Generator row %d refers to unknown bus "%s".', ...
              k, gen_tbl.('Location Bus'){k});
    end
    genBus(k) = name2idx(n);
end

% Count number-of-units (will be useful for scaling PMAX, costs, etc.)
if ~ismember('Number of Units', gen_tbl.Properties.VariableNames)
    error('"Number of Units" column is missing in Generator Data sheet.');
end

% pre-allocate
nUnits = zeros(Ng0,1);

for k = 1:Ng0
    % read the k-th entry from the table, make sure it is numeric
    val         = gen_tbl.('Number of Units')(k);
    nUnits(k)   = double(val);      % force to double in case it’s int
end

% store it in the case (optional, but convenient)
mpc.nUnits = nUnits;

% quick sanity print (optional)
fprintf('[DEBUG]  Units per generator row: %s\n', mat2str(nUnits.'));


%% --------- 2)  PURGE RENEWABLE ROWS *before* numeric matrices ----------
%   - handles “Generation Tech” column flexibly
%   - updates gen_tbl, genBus, nUnits, Ng
%   - saves dropped tags & buses in  mpc.RE_info
%   - To remove renewable gen for keep RE
% ------------------------------------------------------------------------
hdr = gen_tbl.Properties.VariableNames;
techIdx = find(contains(lower(hdr),'generation') & contains(lower(hdr),'tech'), 1);

% capture Number-of-Units column *before* any purge
if ismember('Number of Units', hdr)
    nUnits = gen_tbl.('Number of Units');   % column vector (Ng0 × 1)
else
    nUnits = ones(height(gen_tbl),1);       % default 1 if column absent
end

mpc.RE_info   = table([],[],'VariableNames',{'tag','bus'});   % default
units_per_row = nUnits;         % keep a copy that will be purged in‐step

if isempty(techIdx)
    warning('[build_mpc_from_excel]  "Generation Tech" column not found – no rows removed.');

else
    tech   = lower(strtrim(string(gen_tbl{:, techIdx})));
    tech(ismissing(tech)) = "";                 % convert <missing> to ""
    REkeys = {'wind','solar','pv','hydro','cst','battery','storage'}; % Can add more tags from mast code

    isRE = false(height(gen_tbl),1);
    for k = 1:numel(REkeys)
        isRE = isRE | contains(tech, REkeys{k});
    end

    if any(isRE)
        fprintf('[build_mpc_from_excel]  Dropping %d renewable rows …\n', nnz(isRE));

        % remember dropped rows  (for PD offset later)
        dropNames = string(gen_tbl.('Generator Name')(isRE));
        dropTags  = matlab.lang.makeValidName(lower(strtrim(dropNames)));
        dropBus   = genBus(isRE);
        mpc.RE_info = table(dropTags, dropBus, ...
                            'VariableNames', {'tag','bus'});

        % synchronised deletion
        gen_tbl(isRE , :) = [];
        genBus(isRE)      = [];
        units_per_row(isRE) = [];      
    end
end

% final generator count and unit vector 
Ng              = height(gen_tbl);
mpc.nUnits      = units_per_row;        
fprintf('[DEBUG]  Units per generator row: %s\n', mat2str(mpc.nUnits.'));
% -----------------------------------------------------------------------


%% -------- 3)  LIMITS, COSTS, NUMERIC MATRICES 
Pmax = gen_tbl.('Maximum Real Power (MW)');   Pmax = Pmax(:);
Pmin = gen_tbl.('Minimum Real Power (MW)');   Pmin = Pmin(:);
Qmax = gen_tbl.('Maximum Reactive Power (MVar)');
Qmin = gen_tbl.('Minimum Reactive Power (MVar)');

Pg0  = Pmin;                       % flat start
Qg0  = max(Qmin,0);
Vg   = ones(Ng,1);
status = ones(Ng,1);

mBase  = mpc.baseMVA * ones(Ng,1);
zero8  = zeros(Ng,8);
ramp4  = zeros(Ng,4);
apf    = zeros(Ng,1);

mpc.gen = [ genBus Pg0 Qg0 Qmax Qmin Vg mBase status Pmax Pmin ...
            zero8 ramp4 apf ];

startup  = gen_tbl.('Start up Cost ($)');
shutdown = gen_tbl.('Shut down Cost ($)');
c1       = gen_tbl.('Variable Cost ($/MW)');
c0       = gen_tbl.('Fix Cost ($)');
c2       = zeros(Ng,1);

mpc.gencost = [ 2*ones(Ng,1) startup shutdown 3*ones(Ng,1) c2 c1 c0 ];

mpc.gen_name = gen_tbl.('Generator Name');
mpc.gen_idx  = containers.Map(mpc.gen_name,1:Ng);


%% ------------------------------------------------------------------------
%% 3)  EXPAND CAPACITIES & COSTS BY  “Number of Units”
%% ------------------------------------------------------------------------
%  * mpc.nUnits  – column-vector (Ng × 1) created in the purge section
%  * We multiply …
%      • real-power limits   PMAX  PMIN   (and the initial dispatch Pg0)
%      • reactive limits     QMAX  QMIN   (if they matter to you)
%      • start-up / shut-down cost
%      • fixed cost term     (C0)  in gencost
%    The linear cost ($/MW)  (C1) stays *per-MW* so we leave it untouched.


define_constants      % brings in PG QG PMAX PMIN QMAX QMIN, etc.

u = mpc.nUnits;                       % Ng × 1   (e.g. [1;1;6;10])
U = repmat(u , 1 , size(mpc.gen,2));  % Ng × 21  broadcast helper

%% ----- GEN matrix -------------------------------------------------------
colsScaleGEN = [ PG  QG  PMAX  PMIN  QMAX  QMIN ];   
mpc.gen(:, colsScaleGEN) = mpc.gen(:, colsScaleGEN) .* u;

%% ----- GENCOST matrix ---------------------------------------------------
%  [model  startup  shutdown  ncost  C2  C1  C0]
%            2         3                  7  (column numbers)
mpc.gencost(:, 2) = mpc.gencost(:, 2) .* u;   % startup   $
mpc.gencost(:, 3) = mpc.gencost(:, 3) .* u;   % shutdown  $
mpc.gencost(:, 7) = mpc.gencost(:, 7) .* u;   % fixed cost C0 ($)
u = mpc.nUnits;                            

%% ----- sanity print -----------------------------------------------------
fprintf('[DEBUG]  Applied unit-multipliers : %s\n', mat2str(u.'));
fprintf('         PMAX totals now = %s MW\n', mat2str(mpc.gen(:,PMAX).'));

%% Checker if mpc is correct 

% -------- GEN ------------------------------------------------------------
ghdr = {'GEN_BUS','PG','QG','QMAX','QMIN','VG','MBASE', ...
        'GEN_STATUS','PMAX','PMIN','Units'};

Tgen = array2table([mpc.gen(:,1:10)  u], 'VariableNames', ghdr);

fprintf('\n--- GEN MATRIX (%d x 21, first 10 shown) ---\n', Ng);
disp(Tgen(1:min(10,Ng), :));

% -------- GENCOST --------------------------------------------------------
chdr = {'MODEL','STARTUP','SHUTDOWN','NCOST','C2','C1','C0','Units'};

Tcost = array2table([mpc.gencost  u], 'VariableNames', chdr);

fprintf('\n--- GENCOST MATRIX (%d x 7) ---\n', Ng);
disp(Tcost);

end











