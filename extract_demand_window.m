function D = extract_demand_window(cfgFile, busFile)
% EXTRACT_DEMAND_WINDOW  Return a demand matrix by *hour index* (1-based).
%
%   D = EXTRACT_DEMAND_WINDOW('config.json','5bus_New.xlsx')
%
%   • Reads horizon_days from config.json
%   • For every bus, takes the *first* Nt rows of its trace file
%     (or from start_hour, if that field exists in the JSON).
%   • No calendar / datetime matching is performed.
%
%   Output struct
%   -------------
%     D.busNames   nBus×1 string
%     D.hourIdx    1×Nt   double     (e.g. 1 : 120)
%     D.values     nBus×Nt double    (already scaled by weightage)
% ------------------------------------------------------------------------

%% ---------- CONFIG (horizon length, optional start hour) ---------------
cfg = jsondecode(fileread(cfgFile));

Nt  = cfg.planning.horizon_days * 24;          % total #hours
h0  = 1;                                       % default start index
if isfield(cfg,'start_hour') && cfg.start_hour>=1
    h0 = cfg.start_hour;                       % optional override
end

%% ---------- BUS meta ----------------------------------------------------
info = get_demand_info(busFile);               % BusName, TraceName, Weight
nBus = height(info);

M = zeros(nBus, Nt);                           % pre-allocate

%% ---------- Trace cache -------------------------------------------------
cache = containers.Map('KeyType','char','ValueType','any');

for b = 1:nBus
    fstem = strtrim(info.TraceName(b));
    if fstem=="",  continue,  end

    if ~isKey(cache, fstem)                    % load once
        cache(fstem) = read_demand_trace(fstem);   % uses Demand\…
    end
    tr = cache(fstem);                         % struct: tr.val (column)

    idx  = h0 : h0+Nt-1;                       % wanted rows
    if idx(end) > numel(tr.val)
        error('Trace %s shorter than %d hours.', fstem, Nt + h0 - 1);
    end
    M(b,:) = info.Weight(b) * tr.val(idx).';
end

%% ---------- package -----------------------------------------------------
D.busNames = info.BusName;           % nBus×1
D.hourIdx  = h0 : h0+Nt-1;           % 1×Nt
D.values   = M;                      % nBus×Nt
end
