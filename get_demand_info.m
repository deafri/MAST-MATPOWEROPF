function info = get_demand_info(busFile)
% GET_DEMAND_INFO  Extract Demand-Trace names and weightings from a bus file.
%
%   info = GET_DEMAND_INFO('5bus_New.xlsx')
%
%   Looks (case-/space-insensitive) for columns
%       • Bus Name
%       • Demand Trace Name
%       • Demand Trace Weightage   
%
%   Returns a table with variables:
%       BusName   (string)
%       TraceName (string)
%       Weight    (double)


%% 1) Read the “Bus Data” sheet
opts  = detectImportOptions(busFile, 'Sheet','Bus Data', ...
                            'VariableNamingRule','preserve');
bus   = readtable(busFile, opts);

vars  = strip(bus.Properties.VariableNames);      % original headers
lvars = lower(regexprep(vars,'\s+',''));          

% Helper to locate a column 
findCol = @(tag) find(strcmpi(lvars, lower(regexprep(tag,'\s+',''))), 1);

colBus    = findCol('BusName');
colTrace  = findCol('DemandTraceName');
colWeight = findCol('DemandTraceWeightage');

assert(~isempty(colBus)  && ~isempty(colTrace), ...
       'Required columns “Bus Name” and/or “Demand Trace Name” not found.');

%% 2) Collect data -------------------------------------------------------
BusName  = string(bus{:, colBus});
TraceName= string(bus{:, colTrace});

if isempty(colWeight)
    Weight = ones(height(bus),1);
else
    Weight           = bus{:, colWeight};
    Weight(ismissing(Weight) | isnan(Weight)) = 1;
end

info = table(BusName, TraceName, Weight);
end
