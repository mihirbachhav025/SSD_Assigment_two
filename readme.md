# Delivery Analytics System

**Course:** CS6.302 Software System Development  
**Database:** MySQL 8.0  
**GitHub Repo:** https://github.com/mihirbachhav025/SSD_Assigment_two

---s

## ABOUT

This project processes ~830,000 raw event logs from a food delivery app (~100,000 orders). It calculates performance stats for drivers and customers and saves them into two summary tables: `deliverystatistics` and `requestorstatistics`.

---

## Assumptions

1. **Order Date:** The month and year of an order are always based on the very first time the order became `PendingAssignment`.
2. **Assigning Credit to Drivers:**
   - **For stage times (`TimetoAccept`, `TimetoPickup`, `TimetoArriveatDoorStep`):** Credit goes to the specific driver who actually completed that step.
   - **For total time (`TimetoDeliver`):** Credit goes to the driver who completed the final delivery.
   - **Empty Driver IDs:** Rows where `PartnerID` is blank (`''`) during `PendingAssignment` are ignored for driver stats, but the order itself is still counted.
3. **Data Cleanup:** 
   - Time metrics are only calculated if the start and end timestamps exist and are in the correct order.
   - If a status appears twice for an order, we take the earliest timestamp.
4. **Safe Re-runs:** Running the procedures again clears the target tables first (`TRUNCATE`), so data never duplicates.

---

## Assumption behind KPIs

The `requestorstatistics` table tracks customer habits using these metrics:

* **TotalOrdersPlaced & TotalDelivered:** Shows how active a customer is and how many of their orders actually reach them.
* **TotalCancelled & CancellationRate (`%`):** Shows how often a customer cancels. High numbers usually mean they got tired of waiting for a driver.
* **TotalDeliveryFailed & FailureRate (`%`):** Shows how often deliveries failed, which usually points to wrong address details or lost drivers.
* **AvgTimeToDeliver:** The average minutes it took for orders to reach the customer. This shows if a customer is getting fast or slow service.
* **MostUsedPIN:** The area code where the customer orders most often. Useful for knowing where demand is highest.
* **MostFrequentPartnerID:** The driver who delivers to this customer most often.

---

## Cursor vs. Set-Based Processing

**Metric Analyzed:** Stage duration times (`TimetoAccept`, `TimetoPickup`, etc.).

We used an explicit cursor inside `PopulateDeliveryStatistics()` to loop through rows sequentially and calculate stage times. However, this can also be done using set-based queries with window functions like `LEAD()` or `LAG()`. 

A set-based approach is much faster because the database runs operations in parallel instead of processing rows one by one. The downside is that window functions require nested subqueries and use more memory when handling large datasets, whereas cursors use less memory and make step-by-step logic easier to read.

---

## How to Run

1. Load your CSV data into `2026201056_delivery_data_pins_stg`.
2. Run `solution.sql` in MySQL Workbench to create the tables and procedures.
3. Run these commands to populate the data:

```sql
-- Calculate driver stats
CALL PopulateDeliveryStatistics();
SELECT COUNT(*) FROM 2026201056_deliverystatistics;

-- Calculate customer stats
CALL PopulateRequestorStatistics();
SELECT COUNT(*) FROM 2026201056_requestorstatistics;