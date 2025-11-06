function tr = read_demand_trace(traceName)
% READ_DEMAND_TRACE  Load one hourly demand-profile file.
%
%   tr = READ_DEMAND_TRACE("NSW_RefYear_2023_STEP_CHANGE_POE10")
%
% Output
% ------
%   tr.time   datetime column vector  (one row per hour)
%   tr.val    double   column vector  (MW, same length)
%


%% 1) locate Demand folder & file
thisDir   = fileparts(mfilename('fullpath'));
demandDir = fullfile(thisDir, 'Demand'); % Demand files locations

fx = fullfile(demandDir, traceName + ".xlsx");
fc = fullfile(demandDir, traceName + ".csv");
if     isfile(fx), file = fx;
elseif isfile(fc), file = fc;
else
    error('Trace %s(.xlsx|.csv) not found in %s', traceName, demandDir);
end

%% 2) read raw table (header-agnostic)
opts = detectImportOptions(file,'VariableNamingRule','preserve');
opts = setvaropts(opts, opts.VariableNames, 'TreatAsMissing',{''});
T    = readtable(file, opts, 'ReadVariableNames', false);

if any(varfun(@(c)ischar(c)|isstring(c), T(1,1:min(4,width(T))), ...
              'Output','uniform'))
    T(1,:) = [];                     % drop textual header row
end
T.Properties.VariableNames = "Var" + (1:width(T));

%% 3) numeric matrix
S = strings(size(T));             % strip commas → numeric
for c = 1:width(T),  S(:,c) = string(T{:,c});  end
M = str2double(strrep(S, ',', ''));

%% 4) Date and time 

cols = 1:width(M);

isInt      = @(v) all(mod(v(~isnan(v)),1)==0);
inRange    = @(v,a,b) all((v>=a & v<=b) | isnan(v));

% Year: integer 1900-2100  (no uniqueness requirement)
candY = cols(arrayfun(@(c) isInt(M(:,c)) && inRange(M(:,c),1900,2100), cols));

% Month: integer 1-12, NOT the same column as Year
candM = cols(arrayfun(@(c) isInt(M(:,c)) && inRange(M(:,c),1,12), cols));
candM = setdiff(candM, candY);

% Day: integer 1-31, at least two different values, distinct from Y & M
candD = cols(arrayfun(@(c) isInt(M(:,c)) && inRange(M(:,c),1,31) ...
                               && numel(unique(M(~isnan(M(:,c)),c))) > 1, cols));
candD = setdiff(candD, [candY candM]);

% pick the **left-to-right** earliest valid triple
cY = [];  cM = [];  cD = [];
for y = candY
    m = candM(candM>y);               % month must be to the right of year
    d = candD(candD>y);               % day  must be to the right of year
    if ~isempty(m)
        m = m(1);                     % first month column to the right
        d = d(d>m);                   % day must be to the right of month
        if ~isempty(d)
            cY = y; cM = m; cD = d(1);
            break
        end
    end
end



assert(~isempty(cY)&&~isempty(cM)&&~isempty(cD), ...
       'Cannot unambiguously detect Year / Month / Day columns in %s', file);

%% 4b) first hour column  
cH1 = max([cY cM cD]) + 1;              % hour “1” is the next column
assert(cH1 + 23 <= width(M), ...
       'Need 24 hourly columns after Day column in %s', file);

%% 5) build hourly timetable
nDay  = size(M,1);
val   = NaN(nDay*24,1);
time  = NaT(nDay*24,1);
p = 1;
for r = 1:nDay
    if isnan(M(r,cY)), continue, end
    base = datetime(M(r,cY), M(r,cM), M(r,cD));
    val (p:p+23) = M(r, cH1:cH1+23);
    time(p:p+23) = base + hours(0:23);
    p = p + 24;
end

tr = struct('time', time, 'val', val);
end
