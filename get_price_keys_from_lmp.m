function [priceKeys, timeVar] = get_price_keys_from_lmp(lmpFile)
% GET_PRICE_KEYS_FROM_LMP  Return price-key columns from LMP Excel/CSV.
%   [priceKeys, timeVar] = get_price_keys_from_lmp('LMP_hourly.csv')
%
% - priceKeys : string array of column names to be used as price keys (buses)
% - timeVar   : detected time-like column name ('' if none)
%
% Notes:
% - Works with .csv, .xlsx, .xls, etc. (readtable).
% - Treats columns named like 'Hour', 'Time', 'Datetime', 'Timestamp', 't' as time columns.

tbl = readtable(lmpFile);
vars = string(tbl.Properties.VariableNames);

% Heuristics to ignore time columns
timeCandidates = ["Time","Datetime","Timestamp","Hour","t","TIME","HOUR"];
hasTime = ismember(lower(vars), lower(timeCandidates));
timeVar = "";
if any(hasTime)
    timeVar = vars(find(hasTime,1,'first'));
end

% Price keys are all non-time columns
priceKeys = vars(~hasTime);

% Defensive: ensure we have at least one price key
if isempty(priceKeys)
    error('No price-key columns found. Check your LMP file headers.');
end
end
