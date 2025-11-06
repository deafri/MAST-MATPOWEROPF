function mpc = check_hourcase(mpc, commitRow, dispRow, hIdx)
%CHECK_HOURCASE  Edit MPC for a single hour (no PF/OPF inside).
% Inputs
%   mpc        – MATPOWER case (already built)
%   commitRow  – timetable row with *_On   (unit counts)  from read_mast_dispatch
%   dispRow    – timetable row with *_Pg   (and *_Qg)     "
%   hIdx       – hour index (for log only)

define_constants
Ng = size(mpc.gen,1);   Nb = size(mpc.bus,1);

canon = @(s) matlab.lang.makeValidName(lower( ...
        regexprep(s,{'^status_var_','^pwr_gen_var_','_on$','_pg$'},'')));

vn = dispRow.Properties.VariableNames;   % <── add this line

if nargin < 4, hIdx = 1; end
log = @(s) fprintf('[h %d] %s\n', hIdx, s);

%% ------------------------------------------------------- constants
define_constants;
Ng = size(mpc.gen,1);     Nb = size(mpc.bus,1);

%% ------------------------------------------------------- tiny helpers
canon   = @(s) char(matlab.lang.makeValidName( ...
             lower(regexprep(s, {'^status_var_','^pwr_gen_var_','_on$','_pg$','_qg$'},''))));
tag2row = containers.Map( ...
             cellfun(@(c)canon(c), mpc.gen_name, 'uni',0), ... % keys
             num2cell(1:Ng));                                  % values

%% ------------------------------------------------------- (1) UNIT-ON limits
% To find the out of the total no of units a generator has, how many is on
% Formatting fixes
for v = commitRow.Properties.VariableNames
    v = char(v);                               
    if endsWith(v, '_On', 'ignorecase',true)
        tag = canon(v);
        if tag2row.isKey(tag)
            g     = tag2row(tag);
            nOn   = commitRow{1, v};
            nTot  = mpc.nUnits(g);

            if nOn == 0                              
                mpc.gen(g, GEN_STATUS)      = 0;
                mpc.gen(g, [PG PMAX PMIN])  = 0;
            else                                       
                pmaxU = mpc.gen(g, PMAX) / nTot;
                pminU = mpc.gen(g, PMIN) / nTot;
                mpc.gen(g, [PMAX PMIN]) = [pmaxU pminU] * nOn;
                mpc.gen(g, GEN_STATUS)  = 1;
            end
        end
    end
end

%% ── 2)  Overwrite PG / QG from hourly dispatch  ───────────────────
for g = 1:Ng
    tag = canon(mpc.gen_name{g});
    % ---- active power --------------------------------------------------
    % preferred order : Pwr_Gen_var_*  then  *_Pg
    vname = '';
    pat1  = ['Pwr_Gen_var_' tag];          % Naming Convention from mast
    pat2  = [tag '_Pg'];                   
    if ismember(lower(pat1), lower(vn))
        vname = vn{strcmpi(vn, pat1)};
    elseif ismember(lower(pat2), lower(vn))
        vname = vn{strcmpi(vn, pat2)};
    end
    if ~isempty(vname)
        mpc.gen(g, PG) = dispRow{1, vname};
    end

    % ---- reactive power  -------------------------------------
    vq = '';
    patQ1 = ['Pwr_Gen_var_' tag(1:end-2) '_Qg'];  
    patQ2 = [tag '_Qg'];
    if ismember(lower(patQ1), lower(vn))
        vq = vn{strcmpi(vn, patQ1)};
    elseif ismember(lower(patQ2), lower(vn))
        vq = vn{strcmpi(vn, patQ2)};
    end
    if ~isempty(vq)
        mpc.gen(g, QG) = dispRow{1, vq};
    end
end

%% --- 2b) finalise PMIN / PMAX so that PMIN ≤ PG ≤ PMAX ---------------
for g = 1:Ng
    if ~mpc.gen(g, GEN_STATUS)          % Ignore rows that are off
        continue
    end
    pg  = mpc.gen(g, PG);
    pmax= mpc.gen(g, PMAX);
    pmin= mpc.gen(g, PMIN);
    
    if pg < pmin - 1e-6    % Forcing dispatch values for p_min and p_max         
        pmin = pg;
    end
    if pg > pmax + 1e-6      
        pmax = pg;
    end
    mpc.gen(g, [PMIN PMAX]) = [pmin pmax];
end

% For bus slack
isOn = accumarray(mpc.gen(:,GEN_BUS), mpc.gen(:,GEN_STATUS)>0, [Nb 1]);
mpc.bus(mpc.bus(:,BUS_TYPE)==PV & ~isOn, BUS_TYPE) = PQ;

slack = find(mpc.bus(:,BUS_TYPE)==REF);
if isempty(slack)
    pgBus = accumarray(mpc.gen(:,GEN_BUS), mpc.gen(:,PG), [Nb 1]);
    [~,b] = max(pgBus);  mpc.bus(b,BUS_TYPE) = REF;
elseif numel(slack) > 1
    pgBus = accumarray(mpc.gen(:,GEN_BUS), mpc.gen(:,PG), [Nb 1]);
    [~,k] = max(pgBus(slack));
    mpc.bus(setdiff(slack, slack(k)), BUS_TYPE) = PV;
end

%% (4) widen Q & cost
on = find(mpc.gen(:,GEN_STATUS));
mpc.gen(on,[QMAX QMIN]) = repmat([1e6 -1e6], numel(on),1);
mpc.gencost(on,1) = 2;              % polynomial
mpc.gencost(on,4) = 3;              % ncost = 3
mpc.gencost(on,5) = max(mpc.gencost(on,5), 1e-4);   % C2 >= 1e-4


%% (5) copper-plate tweaks
mpc.branch(:,[BR_R BR_X]) = mpc.branch(:,[BR_R BR_X])*0.01; % Adjust branch res
mpc.branch(:,BR_B)        = 0; % Adjust branch induc
mpc.branch(:,[RATE_A RATE_B RATE_C]) = Inf;
log('R&X ×0.01, BR_B = 0, RATE = Inf');

%% (6) PMIN vs load
posLoad = sum(max(mpc.bus(:,PD),0));
if sum(mpc.gen(:,PMIN)) > posLoad + 1e-6
    mpc.gen(:,PMIN) = mpc.gen(:,PMIN)*posLoad/sum(mpc.gen(:,PMIN));
end
end