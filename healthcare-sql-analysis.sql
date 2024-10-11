--1. Update the demography table. Add a random age for each patient that falls within their respective age category. This newly added age should be an integer.
--Add New Column 'age' to demography table

ALTER TABLE IF EXISTS public.demography
ADD COLUMN age INTEGER;

--UPDATE 'age' with random age for each patiente based on 'agecat'

UPDATE demography
SET age =FLOOR(CAST(LEFT(agecat, 2) AS INTEGER) + (RANDOM() * 7));

--2. Calculate patient's year of birth using admission date from the hospitalization_discharge and add to the demography table.

--Add column 'year_of_birth' to demography table
ALTER TABLE IF EXISTS public.demography
ADD COLUMN year_of_birth INTEGER;

--Calculate Update column 'year_of_birth' in demograhy table using 'admissin_date' column in hospitilaition_date' table 

UPDATE demography d
SET year_of_birth = (extract(year from h.admission_date)) - d.age
FROM hospitalization_discharge h
WHERE h.inpatient_number=d.inpatient_number;

--3. Create a User defined function that returns the age in years of any patient as a calculation from year of birth

CREATE OR REPLACE FUNCTION patient_age_calc(inpatient_id bigint) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
patient_age INTEGER;
BEGIN
SELECT EXTRACT(YEAR FROM CURRENT_DATE) - year_of_birth into patient_age
from public.demography
where inpatient_number = inpatient_id;
IF NOT FOUND THEN
RAISE EXCEPTION 'Patient Id % Not found',inpatient_id;
END IF;
RETURN patient_age;
END;
$$;


--4. What % of the dataset is male vs female?

select 
COALESCE(gender,'Unknown') as gender_category,
CONCAT(ROUND(count(gender) * 100.0 / SUM(COUNT(*)) OVER (),0),'%') AS gender_percentage
from public.demography
where gender != 'Unknown'
group by gender_category

--5. How many patients in this dataset are farmers?

SELECT COUNT(inpatient_number) as count_patinets_farmers FROM demography 
WHERE occupation = 'farmer';


--6. Group the patients by age category and display it as a pie chart

select agecat,  count(agecat) 
from public.demography
where agecat IS NOT NULL
group by  agecat
order by agecat ASC

--7. Divide BMI into slabs of 5 and show the count of patients within each one, without using case statements.

WITH BMI AS
(select ROUND(CAST(BMI AS numeric),2) as bmi_rounded,count(bmi) as bmi_count
from public.demography
group by bmi_rounded
order by bmi_rounded ASC)
SELECT 
width_bucket(bmi_rounded,array[0,18.5,25,30,35]) as bmi_bucket,
int4range(CAST(min(BMI_rounded) as integer),CAST(max(BMI_rounded) as integer),'()')as starting_ending_range,
COUNT(bmi_count) as count_bmi
FROM BMI
GROUP BY bmi_bucket
ORDER BY bmi_bucket ASC


--8. What % of the dataset is over 70 years old

SELECT ROUND(COUNT(age)*100/(select count(inpatient_number) from public.demography),0) as percentage_over_70
FROM public.demography
where age >70

--9. What age group was least likely to be readmitted within 28 days

WITH CTE AS
(select d.agecat as least_likely_readmission_agecat_within_28_days, 
COUNT(hd.re_admission_within_28_days)  
from public.hospitalization_discharge hd
JOIN public.demography d
ON hd.inpatient_number = d.inpatient_number
group by d.agecat
order by COUNT(hd.re_admission_within_28_days) ASC
LIMIT 1)
SELECT least_likely_readmission_agecat_within_28_days
from CTE

--10. Create a procedure to insert a column with a serial number for all rows in demography.

CREATE OR REPLACE PROCEDURE public.generate_series()
    LANGUAGE 'sql'
  AS $BODY$
ALTER TABLE IF EXISTS public.demography
    ADD COLUMN series SERIAL;
$BODY$;

-- Shows Series column with values generated:

Select * from public.demography;  

--11. What was the average time to readmission among men?
select ROUND(AVG(hd.readmission_time_days_from_admission)) as Avg_readmission_time_days
from public.hospitalization_discharge hd
JOIN public.demography d
ON hd.inpatient_number = d.inpatient_number
AND d.gender='Male'

--12.	Display NYHA_cardiac_function_classification as 
--a.	Class I: No symptoms of heart failure
--b.	Class II: Symptoms of heart failure with moderate exertion
--c.	Class III: Symptoms of heart failure with minimal exertion  and show the most common type of heart failure for each classification

WITH common_heart_failure_classification AS
(WITH classification AS
(select
CASE 
WHEN NYHA_cardiac_function_classification = 1 THEN 'Class I: No symptoms of heart failure'
WHEN NYHA_cardiac_function_classification = 2 THEN 'Class II: Symptoms of heart failure with moderate exertion'
WHEN NYHA_cardiac_function_classification = 3 THEN 'Class III: Symptomsof heart failure with minimal exertion'
ELSE 'Unknown'
END AS NYHA_classification, type_of_heart_failure, 
count(inpatient_number) as count_patinet_id
from public.cardiaccomplications
group by NYHA_cardiac_function_classification, type_of_heart_failure
ORDER BY NYHA_classification, count_patinet_id DESC)
SELECT NYHA_classification, type_of_heart_failure, 
RANK() OVER  (PARTITION BY NYHA_classification ORDER BY count_patinet_id DESC) as ranking
from classification
group by NYHA_classification, type_of_heart_failure, count_patinet_id)
SELECT NYHA_classification, type_of_heart_failure
from common_heart_failure_classification
where ranking =1
and NYHA_classification !='Unknown'

--13.	Identify any columns relating to echocardiography and create a severity score for cardiac function. Add this column to the table
--Below code computes severity score for each of the columns relating to echocardiography:
--Columns identified: lvef, left_ventricular_end_diastolic_diameter_lv, ea, mitral_valve_ems, mitral_valve_ams, tricuspid_valve_return_velocity, tricuspid_valve_return_pressure

--Scoring range:
--0 – Good
--1 - Normal
--2 - Mild
--3 - Moderate
--4 – Severe

--Total Severity score range: 

--Total Score	Severity
--0-3	Low Risk or Normal
--4-6	Mild Dysfunction
--7-9	Moderate Dysfunction
--10-12	Severe Dysfunction
--13+	Dangerous

WITH cardiac_severity_score AS
(SELECT inpatient_number,
CASE
WHEN lvef >70 THEN 0
WHEN lvef BETWEEN 50 AND 70 THEN 1
WHEN lvef BETWEEN 40 AND 49 THEN 2
WHEN lvef BETWEEN 30 AND 39 THEN 3
WHEN lvef < 30 THEN 4
ELSE 0
END AS lvef_score,
CASE
WHEN left_ventricular_end_diastolic_diameter_lv <37 THEN 0
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 37 AND 56 THEN 1
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 57 AND 61 THEN 2
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 62 AND 65 THEN 3
WHEN left_ventricular_end_diastolic_diameter_lv < 65 THEN 4
ELSE 0
END AS lvedd_score,
CASE
WHEN ea >0.8 THEN 0
WHEN ea BETWEEN 0.8 AND 1.5 THEN 1
WHEN ea BETWEEN 0.6 AND 0.8 THEN 2
WHEN ea BETWEEN 0.4 AND 0.6 THEN 3
WHEN ea < 0.4 THEN 4
ELSE 0
END AS ea_score,
CASE
WHEN mitral_valve_ems <0.6 THEN 0
WHEN mitral_valve_ems BETWEEN 0.6 AND 0.9 THEN 1
WHEN mitral_valve_ems BETWEEN 1.0 AND 1.2 THEN 2
WHEN mitral_valve_ems BETWEEN 1.3 AND 1.5 THEN 3
WHEN mitral_valve_ems > 1.5 THEN 4
ELSE 0
END AS mvems_score,
CASE
WHEN mitral_valve_ams >=0.12 THEN 0
WHEN mitral_valve_ams BETWEEN 0.09 AND 0.12 THEN 1
WHEN mitral_valve_ams BETWEEN 0.07 AND 0.09 THEN 2
WHEN mitral_valve_ams BETWEEN 0.05 AND 0.07 THEN 3
WHEN mitral_valve_ams < 0.05 THEN 4
ELSE 0
END AS mvams_score,
CASE
WHEN tricuspid_valve_return_velocity <=2.8 THEN 0
WHEN tricuspid_valve_return_velocity =2.9 THEN 1
WHEN tricuspid_valve_return_velocity BETWEEN 3.0 AND 3.1 THEN 2
WHEN tricuspid_valve_return_velocity BETWEEN 3.2 AND 3.4 THEN 3
WHEN tricuspid_valve_return_velocity >= 3.5 THEN 4
ELSE 0
END AS tvrv_score,
CASE
WHEN tricuspid_valve_return_pressure <=25 THEN 0
WHEN tricuspid_valve_return_pressure BETWEEN 26 AND 35 THEN 1
WHEN tricuspid_valve_return_pressure BETWEEN 36 AND 50 THEN 2
WHEN tricuspid_valve_return_pressure BETWEEN 51 AND 70 THEN 3
WHEN tricuspid_valve_return_pressure < 70 THEN 4
ELSE 0
END AS tvrp_score
from public.cardiaccomplications)
SELECT 
inpatient_number,
lvef_score,
lvedd_score,
ea_score,
mvems_score,
mvams_score,
tvrv_score,
tvrp_score,
(lvef_score +
lvedd_score +
ea_score +
mvems_score +
mvams_score +
tvrv_score+
tvrp_score) as total_severity_score
from cardiac_severity_score

--Below statement adds a new column total_severity_score in cardiacomplications

ALTER TABLE cardiaccomplications
ADD COLUMN total_severity_score INT;

--Below query updates total_severity_score score to cardiaccomplications

UPDATE cardiaccomplications
SET total_severity_score =
(
CASE
WHEN lvef >70 THEN 0
WHEN lvef BETWEEN 50 AND 70 THEN 1
WHEN lvef BETWEEN 40 AND 49 THEN 2
WHEN lvef BETWEEN 30 AND 39 THEN 3
WHEN lvef < 30 THEN 4
ELSE 0
END  +
CASE
WHEN left_ventricular_end_diastolic_diameter_lv <37 THEN 0
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 37 AND 56 THEN 1
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 57 AND 61 THEN 2
WHEN left_ventricular_end_diastolic_diameter_lv BETWEEN 62 AND 65 THEN 3
WHEN left_ventricular_end_diastolic_diameter_lv < 65 THEN 4
ELSE 0
END  +
CASE
WHEN ea >0.8 THEN 0
WHEN ea BETWEEN 0.8 AND 1.5 THEN 1
WHEN ea BETWEEN 0.6 AND 0.8 THEN 2
WHEN ea BETWEEN 0.4 AND 0.6 THEN 3
WHEN ea < 0.4 THEN 4
ELSE 0
END  +
CASE
WHEN mitral_valve_ems <0.6 THEN 0
WHEN mitral_valve_ems BETWEEN 0.6 AND 0.9 THEN 1
WHEN mitral_valve_ems BETWEEN 1.0 AND 1.2 THEN 2
WHEN mitral_valve_ems BETWEEN 1.3 AND 1.5 THEN 3
WHEN mitral_valve_ems > 1.5 THEN 4
ELSE 0
END  +
CASE
WHEN mitral_valve_ams >=0.12 THEN 0
WHEN mitral_valve_ams BETWEEN 0.09 AND 0.12 THEN 1
WHEN mitral_valve_ams BETWEEN 0.07 AND 0.09 THEN 2
WHEN mitral_valve_ams BETWEEN 0.05 AND 0.07 THEN 3
WHEN mitral_valve_ams < 0.05 THEN 4
ELSE 0
END  +
CASE
WHEN tricuspid_valve_return_velocity <=2.8 THEN 0
WHEN tricuspid_valve_return_velocity =2.9 THEN 1
WHEN tricuspid_valve_return_velocity BETWEEN 3.0 AND 3.1 THEN 2
WHEN tricuspid_valve_return_velocity BETWEEN 3.2 AND 3.4 THEN 3
WHEN tricuspid_valve_return_velocity >= 3.5 THEN 4
ELSE 0
END  +
CASE
WHEN tricuspid_valve_return_pressure <=25 THEN 0
WHEN tricuspid_valve_return_pressure BETWEEN 26 AND 35 THEN 1
WHEN tricuspid_valve_return_pressure BETWEEN 36 AND 50 THEN 2
WHEN tricuspid_valve_return_pressure BETWEEN 51 AND 70 THEN 3
WHEN tricuspid_valve_return_pressure < 70 THEN 4
ELSE 0
END )
WHERE inpatient_number IS NOT NULL;

--14.	What is the average height of women in cms?

select ROUND(AVG(height*100)) as avg_height_cm
from public.demography
where gender = 'Female';

--15.	Using the cardiac severity column from q13, find the correlation between hospital outcomes and cardiac severity

select 
CORR(CASE WHEN hd.outcome_during_hospitalization = 'Dead' THEN 1 ELSE 0 END, CAST(cc.total_severity_score as integer)) as corr_dead,
CORR(CASE WHEN hd.outcome_during_hospitalization = 'DischargeAgainstOrder' THEN 1 ELSE 0 END, CAST(cc.total_severity_score as integer)) as corr_DAO,
CORR(CASE WHEN hd.outcome_during_hospitalization = 'Alive' THEN 1 ELSE 0 END, CAST(cc.total_severity_score as integer)) as corr_alive
from public.hospitalization_discharge hd
JOIN public.cardiaccomplications cc
ON hd.inpatient_number = cc.inpatient_number;

--Interpretation of Correlation Coefficient
--0 to 0.1: Very weak positive correlation.
--0.1 to 0.3: Weak positive correlation.
--0.3 to 0.5: Moderate positive correlation.
--0.5 to 0.7: Strong positive correlation.
--0.7 to 1: Very strong positive correlation.
--Negative values: Indicate a negative correlation, where as one variable increases, the other tends to decrease.

--16.	Show the no. of patients for everyday in March 2017. Show the date in March along with the days between the previous recorded day in march and the current.

SELECT 
DATE(admission_date) as Admission_Date,
DATE(admission_date) - LAG(DATE(admission_date)) OVER (ORDER BY DATE(admission_date)) as Difference_in_Days,
COUNT(inpatient_number) as Patient_Count
	FROM public.hospitalization_discharge
	where 
	EXTRACT(YEAR FROM admission_date) ='2017' 
	and EXTRACT(Month FROM admission_date) ='03' 
	GROUP BY 
	DATE(admission_date);
	
--17. Create a view that combines patient demographic details of your choice along with pre-exisiting heart conditions like MI,CHF and PVD

create or replace view cardiac_patients as
	select d.inpatient_number, d.gender, d.occupation, d.age, c.myocardial_infarction, c.congestive_heart_failure, c.peripheral_vascular_disease
	from public.demography d
	join cardiaccomplications c on c.inpatient_number = d.inpatient_number
	where c.myocardial_infarction = 1 or c.congestive_heart_failure = 1 or c.peripheral_vascular_disease = 1;

--select all records from the view.
select * from cardiac_patients;
	

--18. Create a function to calculate total number of unique patients for every drug. Results must be returned as long as the first few characters match the user input.

create or replace function get_count_of_prescribed(name_of_drug text)
returns table (count_of_users bigint, name_of_drugs text)
as
$$
declare first_three_letters text;
begin
	first_three_letters =lower(left(name_of_drug,3));
	return query
	select count(inpatient_number), drug_name
	from public.patient_precriptions
	where lower(drug_name) like first_three_letters||'%'
	group by drug_name;
end
$$language plpgsql;

--calling the function with drug name
select * from get_count_of_prescribed('furo');


--19. break up the drug names in patient_precriptions at the ""spaces"" and display only the second string without using Substring. Show unique drug names along with newly broken up string

select distinct drug_name, split_part(drug_name,' ',2) as second_string
from patient_precriptions;

--20. Select the drug names starting with E and has x in any position after

select distinct drug_name
from patient_precriptions
where drug_name like 'E%x%';

--21. Create a cross tab to show the count of readmissions within 28 days, 3 months,6 months as rows and admission ward as columns

	select * from 
crosstab(
	'
SELECT ''180Days'' as day_range,admission_ward,SUM(re_admission_within_6_months) as count_patients
FROM public.hospitalization_discharge
GROUP BY hospitalization_discharge.admission_ward
UNION ALL	
	SELECT ''28Days'' as day_range,admission_ward,SUM(re_admission_within_28_days) as count_patients
FROM public.hospitalization_discharge
 GROUP BY hospitalization_discharge.admission_ward
UNION ALL
SELECT ''90Days'' as day_range,admission_ward,SUM(re_admission_within_3_months) as count_patients
FROM public.hospitalization_discharge
 GROUP BY hospitalization_discharge.admission_ward
UNION ALL
SELECT ''DWithin6Months'' as day_range,admission_ward,SUM(death_within_6_months) as value
FROM public.hospitalization_discharge
GROUP BY hospitalization_discharge.admission_ward	
	',
	'SELECT DISTINCT admission_ward FROM hospitalization_discharge details ORDER BY admission_ward ASC') 
	as adm_columns(day_range varchar,Cardiology int,GeneralWard int,ICU int, Others int);   


--22. Create a trigger to stop patient records from being deleted from the demography table

create or replace function deletion_not_allowed()
returns trigger as
$$
begin
	raise exception 'Deletion is not allowed on this table.';
	return null;
end
$$ language plpgsql;

create trigger no_delete_demography
before delete on public.demography
for each row execute function deletion_not_allowed();

--query to test deletion on demography table
delete from demography where inpatient_number = 5;

--23. What is the total number of days between the earliest admission and the latest

select (max(admission_date)::date-min(admission_date)::date) as day_interval_between_first_and_last_admission
from hospitalization_discharge;

--24. Divide discharge day by visit times for any 10 patients without using mathematical operators like '/'

select inpatient_number,dischargeday, visit_times, div(dischargeday,visit_times) as division_result
from hospitalization_discharge
limit 10;

--25. Show the count of patients by first letter of admission_way.

select substring(admission_way,1,1) as first_letter_of_admission_way,count(inpatient_number)
from hospitalization_discharge
group by admission_way;

--26. Display an array of personal markers:gender, BMI, pulse, MAP for every patient. The result should look like this

select d.inpatient_number, array[d.gender, cast(cast(d.bmi as decimal(10,2)) as text), cast(cast(l.pulse as decimal(10,2)) as text), cast(cast(l.map_value as int) as text)] as markers
from demography d, labs l
where d.inpatient_number = l.inpatient_number;

--27. Display medications With Name contains 'hydro' and display it as 'H20'.

--For this query we also considered drug names that contained ‘Hydro’ with capital H.
--Any drug name that contains ‘hydro’ or ‘Hydro’ will be replaced with H2O.

select distinct drug_name, replace(lower(drug_name),'hydro','H2O') as modified_drug_name from patient_precriptions
where drug_name ilike '%hydro%';

--28. Create a trigger to raise notice and prevent deletion of the view created in question 17
	
create or replace function view_deletion_not_allowed()
returns event_trigger as
$$
declare
	rec record;
begin
    for rec in select * from pg_event_trigger_dropped_objects()
    loop
        if rec.object_type = 'view' AND rec.object_name = 'cardiac_patients' then
       	raise notice 'Deletion of view cardiac_patients is not allowed';
        end if;
    end loop;
end;
$$language plpgsql;

create event trigger cardiac_patients_view_no_deletion on sql_drop
when TAG in ('DROP VIEW')
execute function view_deletion_not_allowed();

--Test trigger by trying to drop the view cardiac_patients.
drop view cardiac_patients;

--29. How many unique patients have cancer?

select distinct count(inpatient_number) as count_of_patients_having_cancer
from patienthistory
where leukemia = 1 or malignant_lymphoma = 1;

--30. Show the moving average of number of patient admitted every 3 months.

select date_trunc('month', admission_date) as ma_month,
  count(inpatient_number) as patients_admitted,
  round((avg(count(inpatient_number)) over (order by date_trunc('month', admission_date) rows between 2 preceding and current row)),2) as moving_average_3_month
from hospitalization_discharge
group by date_trunc('month', admission_date)
order by ma_month;

--31. Write a query to get a list of patient IDs' who recieved oxygen therapy and had a high respiration rate in February 2017

	
select distinct hd.inpatient_number
from hospitalization_discharge hd, labs l
where hd.inpatient_number = l.inpatient_number
and l.respiration >20
and hd.oxygen_inhalation = 'OxygenTherapy'
and extract(month from admission_date) = 02
and extract(year from admission_date) = 2017;

--32. Display patients with heart failure type: "both" along with highest MAP and higest pulse without using limit

--For this question, we are considering the patients with heart failure type: “both” and 
--amongst them we are displaying the patient with highest MAP and the patient with highest pulse.

select cc.inpatient_number, cc.type_of_heart_failure, l.map_value,l.pulse
from cardiaccomplications cc
JOIN labs l
ON  cc.inpatient_number = l.inpatient_number
where  cc.type_of_heart_failure ='Both'
and (l.map_value = (select max(map_value) from labs)
or l.pulse = (select max(pulse) from labs))

--33. Create a stored procedure that displays any message on 
--the screen without using any tables/views.

--creating stored procedure without variable
create or replace procedure stored_procedure()
language plpgsql
as $$
--declaring variable to store the value that is returning from block
declare team text;        
begin 
        select 'Team_29 Primary Key Players' into team;
--raise notice is used to show the output while calling
    raise notice '%',team;
end;
$$;
call stored_procedure();

-- 34. In healthy people, monocytes make up about 1%-9% 
--of total white blood cells. Calculate avg monocyte percentages among each age group

select 
	 agecat,
     round(avg((monocyte_count::numeric/white_blood_cell::numeric)*100),2) as monocyte_percentage
from labs lb
join demography dm 
	on lb.inpatient_number=dm.inpatient_number
group by dm.agecat

--35. Create a table that stores any Patient Demographics 
--	of your choice as the parent table. Create a child table that 
--	contains systolic_blood_pressure,diastolic_blood_pressure 
 --per patient and inherits all columns from the parent table

--droping tables if exists
drop table blood_pressure;
drop table BP_child	;
--parent table
create table blood_pressure
   (inpatient_number bigint PRIMARY KEY,
   gender text,
   bmi double precision,
   agecat text);
--child table
CREATE TABLE BP_child (
    systolic_blood_pressure INTEGER,
    diastolic_blood_pressure INTEGER
   ) INHERITS (blood_pressure);
--insert values
iNSERT INTO BP_child( inpatient_number,gender,bmi,agecat,systolic_blood_pressure,diastolic_blood_pressure)
  select 
     dm.inpatient_number,
      gender,
	bmi,
	agecat,
	systolic_blood_pressure,
	diastolic_blood_pressure
 from demography dm
 join labs lb on
dm.inpatient_number=lb.inpatient_number
--checking the tables
select* from BP_child
select* from blood_pressure

--36. Write a select statement with no table or view attached to it--

select 'TEAM 29 Primary Key Players' as team;

--37. Create a re-usable function to calculate the percentage of 
--patients for any group. Use this function to calculate % of patients
in each admission ward."--

--create the reusable function
create or replace function percentage_patients(tablename text ,group_column text)
returns table (percentage numeric ,count bigint ,column_group text) as
$$
begin
return query    
/*-- this function was unable to take the tablename and column name so used %I as
a placeholder for table name and column name*/
execute format ('select
round((count(inpatient_number)*100.0/(select count(inpatient_number) from %I)),2) as percentage,
count(inpatient_number) as count_by_group,
%I
from %I
group by %I',
	tablename,
	group_column,
	tablename,
	group_column);
end;
$$ language plpgsql


select * from percentage_patients('hospitalization_discharge','admission_ward');

--38. Write a query that shows if CCI score is an even or odd number for any 10 patients

select 
	inpatient_number,
	cci_score,
	case
	when(cci_score::integer % 2)=0 then 'Even Number'
	else 'Odd Number' end
	as cci_score_status
from patienthistory
limit 10;	

--39. Using windows functions show the number of hospitalizations 
--in the previous month and the next month

with monthly_counts as (
select 
	count(inpatient_number) as number_patients,
	extract(month from admission_date) as months
from hospitalization_discharge
group by extract(month from admission_date)
	)
select
   months,
   number_patients,
   lag(number_patients,1,0)over(order by months) as previous_month,
   lead(number_patients,1,0)over(order by months) as next_month
from monthly_counts
order by months;

--40. Write a function to get comma-separated values of patient 
--details based on patient number entered by the user. 
--(Use a maximum of 6 columns from different tables)

create or replace function comma_separated_patient_details()
returns table (
	patient_details text
)
as $$
begin
return query
select
 concat_ws(',',dm.inpatient_number,dm.gender,cc.type_of_heart_failure,hd.outcome_during_hospitalization,round(lb.map_value::numeric,2),pp.drug_name,ph.cci_score)
from demography dm
join cardiaccomplications cc
on cc.inpatient_number=dm.inpatient_number
join hospitalization_discharge hd
on hd.inpatient_number=cc.inpatient_number
join labs lb
on lb.inpatient_number=hd.inpatient_number
join patient_precriptions pp
on pp.inpatient_number=lb.inpatient_number
join patienthistory ph
on ph.inpatient_number=pp.inpatient_number;
end;
$$language plpgsql

--calling function
select * from comma_separated_patient_details()

--41. Which patients were on more than 15 prescribed drugs?
--What was their age and outcome? show the results without using a subquery

without using a subquery*/
select 
	   pp.inpatient_number,
	    age,
	    outcome_during_hospitalization,
	count(drug_name) 
from patient_precriptions pp
join demography dm on 
	dm.inpatient_number=pp.inpatient_number
join hospitalization_discharge hd on
	hd.inpatient_number=dm.inpatient_number
	group by pp.inpatient_number,age,outcome_during_hospitalization
having count(drug_name)>15;


--42. Write a PLSQL block to return the patient ID and gender 
--from demography for a patient 
--if the ID exists and raise an exception 
--if the patient id is not found. 
--Do this without writing or storing a function. 
--Patient ID can be hard-coded for the block*/

--Declaration section
do $$
declare
    gender_p text;
    P_ID bigint := 8;
--execution section		
begin
	if not exists(select inpatient_number from demography where inpatient_number=P_ID) then
	raise notice 'The patient id is not found is %',P_ID;
	else 
    select 
	gender into gender_p 
	from demography 
    where inpatient_number=P_ID;
 raise notice 'The gender is %',gender_p;
end if;
end $$;

--43. Display any 10 random patients along with their type of heart failure

select inpatient_number,type_of_heart_failure from cardiaccomplications
order by random()	
limit 10;

--44. How many unique drug names have a length >20 letters?

select
   count(distinct(drug_name)) As patients_with_drug_g20
 from patient_precriptions
where length(drug_name)>20;

--45. Rank patients using CCI Score as your base. Use a windows function
--to rank them in descending order. With the highest no. of comorbidities ranked 1.

select 
        inpatient_number,
        cci_score,
        rank()over(order by coalesce (cci_score,-1) desc)
        from patienthistory;

--46. What ratio of patients who are responsive to sound vs pain?

select 
  round((select count(inpatient_number)
        from responsivenes 
        where consciousness='ResponsiveToSound' 
        group by consciousness)*1.0/(
        select count(inpatient_number)
        from responsivenes 
        where consciousness='ResponsiveToPain'
        group by consciousness),2) as ratio_of_patients;

--47. Use a windows function to return all admission ways
--along with occupation which is related to the highest MAP value

with admission_rank as
(select  
hd.admission_way, 
d.occupation,
l.map_value,
rank()over(partition by hd.admission_way order by l.map_value desc) as rank_map from hospitalization_discharge hd
join demography d on hd.inpatient_number = d.inpatient_number
join labs l on hd.inpatient_number= l.inpatient_number
order by 1,2,3 )
select distinct admission_way,occupation, map_value
from admission_rank
where rank_map =1;

--48. Display the patients with the highest BMI.

select inpatient_number,
        bmi
        from demography
where bmi=(select max(bmi) from demography);

--49. Find the list of Patients who has leukopenia.

Select inpatient_number, white_blood_cell 
From labs
where white_blood_cell <= 3.0e9;

--50. What is the most frequent weekday of admission?

SELECT to_char(admission_date, 'Day') AS Day_of_week,
Count (*)
FROM hospitalization_discharge
group by Day_of_week;

--51. Create a console bar chart using the '▰' symbol 
--for count of patients in any age category where theres more than 100 patients"

  SELECT agecat,
         COUNT(inpatient_number) as patient_count,
                 RPAD('' ,(COUNT(inpatient_number)/50)::int,'▰'::varchar) AS bar_chart
 FROM demography
 GROUP by agecat
 HAVING COUNT(inpatient_number)>100
 ORDER BY patient_count ASC;

-- 52. Find the variance of the patients' D_dimer value and
 --display it along with the correlation to CCI score and display them together.
 
WITH cte_varaince AS
(
SELECT labs.inpatient_number,
       VARIANCE(labs.d_dimer) over() AS var_dimer   
 FROM labs
        )
  SELECT  var_dimer,
          corr(var_dimer,ph.cci_score)
  FROM cte_varaince AS var
  JOIN patienthistory as ph
  ON var.inpatient_number = ph.inpatient_number
  GROUP BY var_dimer;

--53. Which adm ward had the lowest rate of Outcome Death?

select admission_ward, COUNT(outcome_during_hospitalization) AS death_count
from hospitalization_discharge
where outcome_during_hospitalization = 'Dead'
group by admission_ward,outcome_during_hospitalization
ORDER BY death_count Asc;  

--54. What % of those in a coma also have diabetes. Use the GCS scale to evaluate.

WITH coma_patients AS (
SELECT r.inpatient_number
FROM responsivenes r
WHERE r.gcs <= 8
),
coma_with_diabetes AS (
SELECT 
cp.inpatient_number
FROM 
coma_patients cp JOIN patienthistory ph
ON cp.inpatient_number = ph.inpatient_number
where ph.diabetes = 1)
SELECT 
case 
    when COUNT(coma_patients.inpatient_number) = 0 THEN 0
     else (COUNT(coma_with_diabetes.inpatient_number) * 100) / COUNT(coma_patients.inpatient_number)
         end AS coma_patients_with_diabetes_percentage
FROM coma_patients
LEFT JOIN coma_with_diabetes 
ON coma_patients.inpatient_number = coma_with_diabetes.inpatient_number;

--55. Display the drugs prescribed by the youngest patient

select * from patient_precriptions 
where Inpatient_number = 
(select Inpatient_number from demography 
order by agecat asc
limit 1);

-- 56. Create a view on the public.responsivenes table using the check constraint

create or replace view public.responsivenes_view as
(select inpatient_number,
eye_opening,
verbal_response,
movement,
gcs
from public.responsivenes
where 
gcs between 3 and 15
and eye_opening in (0,1,2,3,4)
and verbal_response in (0,1,2,3,4,5)
and movement in (0,1,2,3,4,5,6))
with check option;


--57. Determine if a word is a palindrome and display true or false. 
--Create a temporary table and store any words of your choice for this question

 create Temporary table temporary_words (
word varchar(100)
 );

insert into temporary_words (word) values
('favor'),
('level'),
('flex'),
('rotor'), 
('public'),
('madam'),
('fixed'), 
('better'),
('radar'),
('expect');

Select * from temporary_words;

select temporary_words ,
case
when word = reverse(word) then 'true'
else 'false'
end as palindrome
from temporary_words;


--58. How many visits were common among those with a readmission in 6 months

select visit_times, count(inpatient_number) as patient_count
from hospitalization_discharge
where re_admission_within_6_months = 1
group by visit_times
order by visit_times
LIMIT 1


--59. What is the size of the database Cardiac_Failure

Select pg_Size_pretty(pg_database_size('Cardiac_Failure')) as 
Cardiac_Failure_Database_Size;

--60. Find the greatest common denominator 
--and the lowest common multiple of the numbers 365 and 300. show it in one query

SELECT GCD(365,300)  AS Graetest_common_denominator,
        LCM(365,300) AS Least_common_multiple;

--61. Group patients by destination of discharge and 
--show what % of all patients in each group was re-admitted within 28 days.
--Partition these groups as 2: high rate of readmission, low rate of re-admission. 
--Use windows functions

with readmission_count as
(select  destinationdischarge, count(inpatient_number) as count_patients,
sum(case when re_admission_within_28_days = 1 then 1 else 0 end) as readmitted_patients
from hospitalization_discharge
group by destinationdischarge),
readmission_percentage AS
(select destinationdischarge,
 count_patients,
 readmitted_patients,
 (readmitted_patients*100.0/count_patients) as readmission_percentage
 from readmission_count
)
select destinationdischarge,
readmission_percentage,
case when readmission_percentage > (select percentile_cont(0.5) within group(order by readmission_percentage) from readmission_percentage)
then 'High'
ELSE 'Low'
END AS readmission_rate_category
from readmission_percentage
group by destinationdischarge,readmission_percentage,readmission_rate_category
order by readmission_rate_category


--62. What is the size of the table labs in KB without the indexes or additional objects

Select pg_Size_pretty(pg_relation_size('labs'));

--63. concatenate age, gender and patient ID with a ';' in between without using the || operator
Select 
 Concat(agecat,'  ;  ',gender, '  ;  ', inpatient_number) as patient_details
 from demography;

-- 64. Display a reverse of any 5 drug names
Select drug_name,
Reverse(drug_name)
from patient_precriptions
order by drug_name asc
limit 5;

--65. What is the variance from mean for all patients GCS score

SELECT inpatient_number,
       gcs,
	   round(avg(gcs) over (),2) AS mean_gcs,
	   variance(gcs) over () AS variance_gcs,
      round(( gcs - avg(gcs) over () )/ ( variance(gcs) over ()),5 )as gcs_variance_from_mean 
	  from responsivenes
	  GROUP BY inpatient_number,gcs;

-- 66. Using a while loop and a raise notice command, print the 7 times table as the result

do $$ 
declare 
	counter integer := 0;
begin 
	while counter < 10 loop 
	    raise notice '7 * % = %',counter,counter * 7;
		counter := counter + 1;
	end loop;
end;
$$;


-- 67. Show month number and month name next to each other(admission_date), 
--     ensure that month number is always 2 digits. eg, 5 should be 05".
   
   SELECT inpatient_number,
           admission_date,
		   (CONCAT(TO_CHAR(DATE_PART('month',admission_date), 'fm00'),
				  ',' ,
				  TO_CHAR(admission_date,'Mon') )) AS Month
   FROM hospitalization_discharge;
   
----68. How many patients with both heart failures had kidney disease or cancer.

SELECT SUM(ph.moderate_to_severe_chronic_kidney_disease) AS Kidney_disease,
	   SUM(ph.leukemia + ph.malignant_lymphoma) AS cancer,
	   count(ph.inpatient_number) AS Total_patients_with_kidneyorcancer
FROM cardiaccomplications AS comp
JOIN patienthistory AS ph
ON comp.inpatient_number = ph.inpatient_number
WHERE type_of_heart_failure = 'Both'
AND( ph.moderate_to_severe_chronic_kidney_disease =1
OR ph.leukemia = 1 OR ph.malignant_lymphoma = 1);
-- did not consider solid_tumor as cancer because ,not all solid_tumor is cancer

-- 69. Return the number of bits and the number of characters for every 
-- value in the column: Occupation

SELECT DISTINCT occupation,
      bit_length(occupation) as number_of_bits,
	  length(occupation)  as number_of_characters
FROM demography
WHERE occupation is not null
GROUP BY occupation;

--70. Create a stored procedure that adds a column to table cardiaccomplications. 
 -- The column should just be the todays date 

CREATE OR REPLACE PROCEDURE pr_date_today ()
	language plpgsql    
as
$$
begin
-- create and update the date_today column to cardiaccomplications table
ALTER TABLE cardiaccomplications 
ADD COLUMN date_today date default current_date;
    commit;
end;
$$;

-- Call the procedure
call pr_date_today();


-- 71. What is the 2nd highest BMI of the patients with 5 highest myoglobin values.
-- Use windows functions in solution 
 
 WITH temp_myoglobin AS
(
SELECT  labs.inpatient_number,
        labs.myoglobin,
		demo.bmi,
		rank() over (ORDER BY labs.myoglobin DESC) AS myoglobin_rank
FROM labs
JOIN demography as demo
ON labs.inpatient_number = demo.inpatient_number
WHERE myoglobin is not null
),temp_bmi AS (
SELECT inpatient_number,
	       myoglobin,
		    round(bmi::numeric, 2),
			rank () over (order by bmi DESC) AS bmi_rank,
	 	    myoglobin_rank from temp_myoglobin 
	WHERE myoglobin_rank  <=5 
	ORDER BY bmi DESC  
)
SELECT * FROM temp_bmi WHERE bmi_rank = 2;


--72. What is the standard deviation from mean for all patients pulse

SELECT inpatient_number,
       pulse,
	   round(avg(pulse) over (),2) AS mean_pulse,
	   round(stddev(pulse) over (),2) AS stddev_pulse,
      round(( pulse - avg(pulse) over () )/ ( stddev(pulse) over ()),5 )as pulse_stdev_from_mean 
	  from labs
	  GROUP BY inpatient_number,pulse;


--73. Create a procedure to drop the age column from demography

	CREATE OR REPLACE PROCEDURE pr_age_del ()
		language plpgsql    
	as
	$$
	begin
	-- Query to delete the age column from demography
	ALTER TABLE demography DROP COLUMN age;

		commit;
	end;
	$$;

	-- call the procedure
	call  pr_age_del();
	
-- 74  What was the average CCI score for those with a BMI>30 vs for those <30

SELECT --COUNT(demo.bmi),
       CASE 
	   WHEN demo.bmi>30 THEN 'BMI>30'
	   WHEN demo.bmi<30 THEN 'BMI<30'
	   END AS bmi_range,
	   AVG(ph.cci_score) AS avg_cci
FROM demography as demo
JOIN patienthistory AS ph
ON demo.inpatient_number = ph.inpatient_number
GROUP BY bmi_range;

-- 75. Write a trigger after insert on the Patient Demography table. 
 --  if the BMI >40, warn for high risk of heart risks 
   
   CREATE  FUNCTION bmi_trigg_fn() -- Create function
RETURNS TRIGGER AS $$
BEGIN
  if NEW.bmi > 40 THEN
  RAISE NOTICE 'High risk of heart risks for patient id % with  BMI (% )',NEW.inpatient_number,NEW.bmi;
  end if;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER bmi_trigg    --- Create trigger
AFTER INSERT ON "demography"
FOR EACH ROW
EXECUTE FUNCTION bmi_trigg_fn();

--Insert records to demography
INSERT INTO demography (inpatient_number,gender,weight,height,bmi,occupation,agecat)
VALUES(987665,'Female',120,1.5,41,'UrbanResident','79-89');


-- 76. Most obese patients belong to which age group and gender. 
 --  You may make an assumption for what qualifies as obese based on your research 
   
 SELECT agecat,
       gender,
	   COUNT(inpatient_number) AS number_obese
FROM demography
WHERE bmi>=30     -- considering 30 as obese
AND gender is not null
GROUP BY agecat,gender
ORDER BY number_obese DESC LIMIT 1;

-- 77. Show all response details of a patient in a JSON array

SELECT array_to_json(array_agg(row_to_json(responsivenes))) AS json_resp
FROM responsivenes;

-- 78. Update the table public.patienthistory. 
 --  Set type_ii_respiratory_failure to be upper case,query the results of the updated table without writing a second query*/

UPDATE     
    patienthistory
SET
    type_ii_respiratory_failure =UPPER(type_ii_respiratory_failure)
    RETURNING type_ii_respiratory_failure;

-- 79. Find all patients using Digoxin or Furosemide using regex

SELECT DISTINCT inpatient_number
FROM patient_precriptions 
WHERE drug_name ~* '(Digoxin|Furosemide)';

-- 80 Using a recursive query, 
 -- show any 10 patients linked to the drug: "Furosemide injection" 

WITH RECURSIVE cte_rec_query
AS (
    SELECT 
	  inpatient_number,
	  drug_name
	FROM
	  patient_precriptions 
    WHERE
	  drug_name = 'Furosemide injection' 
	UNION 
	   SELECT 
	       p.inpatient_number,
	       p.drug_name
	FROM patient_precriptions p
	   INNER JOIN cte_rec_query r1
	   ON r1.inpatient_number = p.inpatient_number  
) 
SELECT * FROM cte_rec_query LIMIT 10 ;
