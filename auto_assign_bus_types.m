function mpc = auto_assign_bus_types(mpc, hIdx)
% AUTO_ASSIGN_BUS_TYPES  Infer MATPOWER bus types from gen status/dispatch.
% - PQ (1) default
% - PV (2) for buses with at least one online generator
% - REF (3) choose a single slack among online-gen buses (highest Pg, fallback Pmax)


    if nargin < 2, hIdx = []; end %#ok<NASGU>

    define_constants; % MATPOWER indices: BUS_TYPE, GEN_BUS, GEN_STATUS, PG, PMAX

    nb = size(mpc.bus, 1);
    ng = size(mpc.gen, 1);

    % 0) Sanity: ensure required fields exist
    assert(isfield(mpc, 'bus') && ~isempty(mpc.bus), 'auto_assign_bus_types: mpc.bus missing/empty');
    assert(isfield(mpc, 'gen') && ~isempty(mpc.gen), 'auto_assign_bus_types: mpc.gen missing/empty');

    % 1) Start with all PQ
    mpc.bus(:, BUS_TYPE) = 1;  % PQ

    % 2) Find online generators
    gen_on = (mpc.gen(:, GEN_STATUS) > 0);
    if ~any(gen_on)
        warning('auto_assign_bus_types: No online generators; keeping all buses PQ.');
        return;
    end

    % 3) Mark PV for any bus that has at least one online generator
    gen_bus_ids = mpc.gen(gen_on, GEN_BUS);                % bus numbers (not row indices)
    [~, bus_rows] = ismember(gen_bus_ids, mpc.bus(:, BUS_I));
    bus_rows = unique(bus_rows(bus_rows > 0));
    mpc.bus(bus_rows, BUS_TYPE) = 2;                       % PV

    % 4) Choose a single REF (slack) among PV buses
    % Preference: highest Pg among online gens; fallback: highest Pmax among online gens.
    Pg = mpc.gen(:, PG);
    Pmax = mpc.gen(:, PMAX);

    % Some pipelines may leave Pg empty/NaN before OPF: handle gracefully
    Pg(~gen_on) = -inf;              % ignore offline
    if all(~isfinite(Pg))
        % Fallback to Pmax
        Pscore = Pmax;
        Pscore(~gen_on) = -inf;
    else
        Pscore = Pg;
    end

    [~, kSlackGen] = max(Pscore);
    slack_bus_num  = mpc.gen(kSlackGen, GEN_BUS);
    slack_bus_row  = find(mpc.bus(:, BUS_I) == slack_bus_num, 1);

    % 5) Enforce exactly one REF
    if isempty(slack_bus_row)
        % Should not happen, but guard.
        warning('auto_assign_bus_types: slack bus not found in bus table; skipping REF assignment.');
        return;
    end
    % Clear any pre-existing REF flags
    mpc.bus(:, BUS_TYPE) = max(mpc.bus(:, BUS_TYPE), 1);   % ensure 1..3 range
    % Set chosen slack
    mpc.bus(slack_bus_row, BUS_TYPE) = 3;                  % REF


    ref_rows = find(mpc.bus(:, BUS_TYPE) == 3);
    if numel(ref_rows) > 1
        ref_rows(ref_rows ~= slack_bus_row) = [];          % keep only the chosen one
        mpc.bus(mpc.bus(:, BUS_TYPE) == 3 & (1:nb)' ~= slack_bus_row, BUS_TYPE) = 2; % revert others to PV
    end


    if ~ismember(slack_bus_num, gen_bus_ids)
        warning('auto_assign_bus_types: chosen REF bus has no online generator; reselecting.');
        % Re-run selection restricted to buses that truly have online gens
        online_bus_nums = unique(gen_bus_ids);
        [~, bus_rows2] = ismember(online_bus_nums, mpc.bus(:, BUS_I));
        mpc.bus(:, BUS_TYPE) = 1;              % reset PQ
        mpc.bus(bus_rows2, BUS_TYPE) = 2;      % PV
        % pick first online as REF
        mpc.bus(bus_rows2(1), BUS_TYPE) = 3;
    end
end
