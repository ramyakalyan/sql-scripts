# Healthcare Data Analysis - SQL Project for Cardiac Failure Insights

This repository contains SQL scripts developed to analyze healthcare data, focusing on cardiac failure. The goal of this project is to extract insights from patient demographics, clinical metrics, and treatment outcomes to assist healthcare professionals in optimizing care for cardiac failure patients.

## Table of Contents
- [Project Overview](#project-overview)
- [SQL Scripts Overview](#sql-scripts-overview)
- [Usage](#usage)
- [Insights Derived](#insights-derived)
- [Future Work](#future-work)

## Project Overview

Cardiac failure is a leading cause of hospitalization and mortality. This project uses SQL queries to provide data-driven insights for healthcare providers. The dataset includes:
- Demographic information (age, gender, occupation)
- Clinical data (BMI, cardiac function metrics like LVEF)
- Treatment outcomes (readmission rates, survival rates)

### Key Objectives:
- Analyze patient demographics (age, gender, occupation).
- Assess cardiac function severity using clinical metrics (LVEF, mitral valve pressure).
- Investigate treatment outcomes and hospital readmission rates.
- Identify time-based trends in patient admissions and outcomes.

## SQL Scripts Overview

The SQL scripts provide detailed insights into patient demographics, cardiac function, and treatment outcomes. These scripts use advanced SQL features like stastical functions, window functions and triggers to generate comprehensive analyses.

### Key Features:
1. **Demographic Analysis**:
   - Analyze patient age, gender, and occupation distribution.
   - Identify specific occupations associated with cardiac failure risks.
   
2. **Cardiac Function Analysis**:
   - Calculate cardiac severity scores using clinical metrics like LVEF, tricuspid valve pressure, and mitral valve measurements.
   - Categorize patients into risk levels (e.g., "Low Risk", "High Risk").

3. **BMI and Health Risks**:
   - Group patients into BMI categories and correlate obesity with cardiac failure severity.
   - Identify patients at higher risk of readmission based on BMI.

4. **Hospital Readmission Rates**:
   - Calculate readmission rates within 28 days, 3 months, and 6 months.
   - Segment patients by age, gender, and cardiac severity levels to identify high-risk groups.

5. **Advanced SQL Techniques**:
   - Use SQL window functions to analyze time-based trends (e.g., moving averages of patient admissions).
   - Implement triggers to ensure data integrity (e.g., preventing deletion of patient records).

### Example Queries:
- **Gender Distribution Analysis**:
   ```sql
   SELECT gender, COUNT(*) AS patient_count,
   CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM public.demography), 2), '%') AS percentage
   FROM public.demography
   GROUP BY gender;
   
## Usage

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/ramyakalyan/healthcare-sql-analysis.git

## Insights Derived

- **Demographic Insights**: Cardiac failure is more prevalent among older patients, especially those over the age of 70. Gender distribution was relatively balanced, though males had a slightly higher incidence of cardiac failure.
- **Cardiac Function**: Patients with lower LVEF scores were more likely to experience adverse outcomes. Early intervention significantly improved outcomes for patients with severe cardiac function deterioration.
- **BMI and Readmission Correlation**: Obesity, particularly in patients aged 50 to 70, was a significant risk factor for cardiac failure and hospital readmission within 6 months.

## Future Work

- **Predictive Analytics**: Use SQL outputs with machine learning models to predict patient outcomes, readmission likelihood, and mortality risk.
- **Enhanced Visualization**: Integrate SQL query results with visualization tools like Tableau, PowerBI, or Python libraries (e.g., Matplotlib) to create dashboards for healthcare professionals.
- **Data Optimization**: Optimize SQL queries for better performance on large datasets, incorporating indexing and query plan analysis to reduce execution time.
