-- Step 1: Clear all data from the Example table in Database1
-- Using TRUNCATE to remove all rows without deleting the table structure.
TRUNCATE TABLE [Database1].dbo.Example;

-- Step 2: Insert distinct Masterkey values into the Example table in Scorecard database
-- This selects unique Masterkeys from Example_Table that match a specific organization 
-- and inserts them into the Scorecard Example table.
INSERT INTO Scorecard.[dbo].Example
SELECT DISTINCT Masterkey
FROM [AggregateDatabase1].dbo.[Example_Table]
WHERE IDOrganization = 279
AND Masterkey LIKE '292%';

-- Step 3: Update patient details in the Example table
-- The update sets patient's first name, last name, date of birth, and client name 
-- in the Scorecard Example table using data from Example_Table in AggregateDatabase1.
UPDATE Example
SET [Patient's First Name] = Pers.PsnFirst,
    [Patient's Last Name] = Pers.PsnLast,
    [Patient's Date of Birth] = Pers.PsnDOB,
    [Client Name] = Pers.PcPPracticeName
FROM [AggregateDatabase1].dbo.[Example_Table] Pers
JOIN Scorecard.Example samp ON Pers.MasterKey = samp.MRN
WHERE Pers.IDOrganization = Pers.IDMasterOrganization
AND Pers.Idstatus = 1;

-- Step 4: Update patient phone numbers with the most recent entry
-- This retrieves the most recent phone number for each patient and updates
-- the Example table with the cleaned phone number format.
UPDATE Example
SET [Patient's Phone Number] = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
LTRIM(RTRIM(A.Phone)), '-', ''), '(', ''), ')', ''), ' ', ''), '/', ''), 'x', ''), '*', ''), 'calls', '')
FROM (
    SELECT Phone.MasterKey, Phone.Phone, Phone.DateUpdated,
           ROW_NUMBER() OVER (PARTITION BY Phone.MasterKey ORDER BY Phone.DateUpdated DESC) AS RN
    FROM [AggregateDatabase1].dbo.[Phone_Table] Phone
    INNER JOIN Scorecard.Example samp ON Phone.MasterKey = samp.MRN
    WHERE PhoneType IN ('CELL', 'HOME')
    AND ISNULL(Phone.Phone, '') <> ''
    AND Phone.Phone NOT LIKE '%[a-z]%'
    AND LEN(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    LTRIM(RTRIM(Phone.Phone)), '-', ''), '(', ''), ')', ''), ' ', ''), '/', ''), 'x', ''), '*', ''), 'calls', '')) = 10
) A
JOIN [AggregateDatabase1].dbo.[Person_Table] j ON A.MasterKey = j.MasterKey
JOIN [AggregateDatabase1].dbo.[Master_Patient_Index_Table] d 
ON j.IDOrganization = d.IDOrganization AND j.IDPerson = d.IDPerson
INNER JOIN Scorecard.dbo.Example Outp ON A.MasterKey = OutP.MRN
WHERE RN = 1;

-- Step 5: Format the patient's phone number for consistency
-- Updates phone numbers to a standard format (xxx-xxx-xxxx).
UPDATE Example
SET [Patient's Phone Number] = SUBSTRING([Patient's Phone Number], 1, 3) + '-' +
                               SUBSTRING([Patient's Phone Number], 4, 3) + '-' +
                               SUBSTRING([Patient's Phone Number], 7, 4);

-- Step 6: Calculate performance metrics based on recommendations
-- This query aggregates recommendation statuses, counts them as Met, Not Met, etc., 
-- and calculates a Performance Rate as a percentage.
SELECT r.ProtCode,
       SUM(CASE WHEN R.Recommendation LIKE '%current' THEN 1 ELSE 0 END) AS [Met],    -- Numerator
       SUM(CASE WHEN R.Recommendation LIKE '%invalid' THEN 1 ELSE 0 END) AS [Not Met],
       SUM(CASE WHEN R.Recommendation LIKE '%incl' THEN 1 ELSE 0 END) AS [Denominator],
       SUM(CASE WHEN R.Recommendation LIKE '%excl' THEN 1 ELSE 0 END) AS [Exclusion],
       SUM(CASE WHEN R.Recommendation LIKE '%exception' THEN 1 ELSE 0 END) AS [Exception],
       CONVERT(Decimal(20,1),
       (CONVERT(Decimal(20,1), SUM(CASE WHEN R.Recommendation LIKE '%current' THEN 1 ELSE 0 END) * 100) /
       (SUM(CASE WHEN R.Recommendation LIKE '%incl' THEN 1 ELSE 0 END) - SUM(CASE WHEN R.Recommendation LIKE '%exception' THEN 1 ELSE 0 END))
       )) AS [Performance Rate %]
FROM [Example].[dbo].(Recommendations) r WITH(NOLOCK)
WHERE (R.Recommendation LIKE '%current'
       OR R.Recommendation LIKE '%Excl' 
       OR R.Recommendation LIKE '%Incl'
       OR R.Recommendation LIKE '%Invalid'
       OR R.Recommendation LIKE '%Exception')
GROUP BY r.ProtCode
ORDER BY 1;
