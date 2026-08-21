create database 2026201056_delivery;

use 2026201056_delivery;

select count(*) from 2026201056_delivery_data_pins_stg;

select * from 2026201056_delivery_data_pins_stg limit 1;

DESCRIBE 2026201056_delivery_data_pins_stg;

-- TRUNCATE TABLE 2026201056_delivery_data_pins_stg;

SHOW VARIABLES LIKE 'local_infile';
SET GLOBAL local_infile = 1;

SHOW VARIABLES LIKE 'local_infile';

SHOW VARIABLES LIKE 'local_infile';

SHOW VARIABLES LIKE 'secure_file_priv';

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/delivery_data_100k_expanded_pins.csv'
INTO TABLE 2026201056_delivery_data_pins_stg
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(
    OrderRequestorID,
    OrderID,
    PartnerID,
    PINCode,
    Status,
    `Timestamp`
);

#DROP TABLE IF EXISTS deliverystatistics;

CREATE TABLE 2026201056_deliverystatistics (
    PINCode INT,
    PartnerID VARCHAR(100),
    MonthofOrder INT,
    YearofOrder INT,

    TotalOrders INT,
    TotalPendingAssignment INT,
    TotalAccepted INT,
    TotalHeadingforPickup INT,
    TotalArrivedatPickup INT,
    TotalPickedUp INT,
    TotalOutforDelivery INT,
    TotalArrivedatDoorStep INT,
    TotalDelivered INT,
    TotalDropped INT,
    TotalDelayedatPickup INT,
    TotalDeliveryFailed INT,
    TotalReturningtoStore INT,
    TotalReturned INT,
    TotalCancelled INT,

    TimetoAccept DECIMAL(10,2),
    TimetoPickup DECIMAL(10,2),
    TimetoArriveatDoorStep DECIMAL(10,2),
    TimetoDeliver DECIMAL(10,2)
);


USE 2026201056_delivery;

DELIMITER $$

DROP PROCEDURE IF EXISTS 2026201056_delivery.PopulateDeliveryStatistics $$

CREATE PROCEDURE 2026201056_delivery.PopulateDeliveryStatistics()
BEGIN

    /* Cursor variables */
    DECLARE done INT DEFAULT 0;

    DECLARE v_OrderID TEXT;
    DECLARE v_PartnerID TEXT;
    DECLARE v_PINCode INT;
    DECLARE v_Status TEXT;
    DECLARE v_Timestamp DATETIME;

    /* Order & Leg tracking state */
    DECLARE v_CurrentOrderID TEXT DEFAULT NULL;
    DECLARE v_PendingTime DATETIME DEFAULT NULL;
    DECLARE v_OrderPIN INT DEFAULT NULL;

    /* Stage-specific timestamps & partners */
    DECLARE v_AcceptPartner TEXT DEFAULT NULL;
    DECLARE v_AcceptedTime DATETIME DEFAULT NULL;

    DECLARE v_PickupPartner TEXT DEFAULT NULL;
    DECLARE v_PickedUpTime DATETIME DEFAULT NULL;

    DECLARE v_DoorstepPartner TEXT DEFAULT NULL;
    DECLARE v_DoorstepTime DATETIME DEFAULT NULL;

    DECLARE v_DeliveryPartner TEXT DEFAULT NULL;
    DECLARE v_DeliveredTime DATETIME DEFAULT NULL;

    DECLARE cur CURSOR FOR
        SELECT
            OrderID,
            PartnerID,
            PINCode,
            Status,
            `Timestamp`
        FROM 2026201056_delivery_data_pins_stg
        ORDER BY
            OrderID,
            `Timestamp`;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    /* Truncate statistics table for idempotent re-runs */
    TRUNCATE TABLE 2026201056_deliverystatistics;

    /* Temporary table for multi-partner stage metrics */
    DROP TEMPORARY TABLE IF EXISTS tmp_stage_metrics;

    CREATE TEMPORARY TABLE tmp_stage_metrics
    (
        OrderID VARCHAR(255),
        PINCode INT,
        PartnerID VARCHAR(255),
        MonthofOrder INT,
        YearofOrder INT,
        StageType VARCHAR(50),
        DurationMinutes DECIMAL(10,2),
        INDEX idx_stage_group (PINCode, PartnerID, MonthofOrder, YearofOrder)
    );

    OPEN cur;

    read_loop: LOOP

        FETCH cur INTO
            v_OrderID,
            v_PartnerID,
            v_PINCode,
            v_Status,
            v_Timestamp;

        /* End of Cursor Processing */
        IF done = 1 THEN
            IF v_CurrentOrderID IS NOT NULL AND v_PendingTime IS NOT NULL THEN
                
                IF v_AcceptedTime IS NOT NULL AND v_AcceptPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_AcceptPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'ACCEPT', TIMESTAMPDIFF(SECOND, v_PendingTime, v_AcceptedTime) / 60.0
                    );
                END IF;

                IF v_PickedUpTime IS NOT NULL AND v_AcceptedTime IS NOT NULL AND v_PickupPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_PickupPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'PICKUP', TIMESTAMPDIFF(SECOND, v_AcceptedTime, v_PickedUpTime) / 60.0
                    );
                END IF;

                IF v_DoorstepTime IS NOT NULL AND v_PickedUpTime IS NOT NULL AND v_DoorstepPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_DoorstepPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'DOORSTEP', TIMESTAMPDIFF(SECOND, v_PickedUpTime, v_DoorstepTime) / 60.0
                    );
                END IF;

                IF v_DeliveredTime IS NOT NULL AND v_DeliveryPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_DeliveryPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'DELIVER', TIMESTAMPDIFF(SECOND, v_PendingTime, v_DeliveredTime) / 60.0
                    );
                END IF;

            END IF;
            LEAVE read_loop;
        END IF;

        /* Transition to new OrderID */
        IF v_CurrentOrderID IS NULL OR v_OrderID <> v_CurrentOrderID THEN

            IF v_CurrentOrderID IS NOT NULL AND v_PendingTime IS NOT NULL THEN

                IF v_AcceptedTime IS NOT NULL AND v_AcceptPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_AcceptPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'ACCEPT', TIMESTAMPDIFF(SECOND, v_PendingTime, v_AcceptedTime) / 60.0
                    );
                END IF;

                IF v_PickedUpTime IS NOT NULL AND v_AcceptedTime IS NOT NULL AND v_PickupPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_PickupPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'PICKUP', TIMESTAMPDIFF(SECOND, v_AcceptedTime, v_PickedUpTime) / 60.0
                    );
                END IF;

                IF v_DoorstepTime IS NOT NULL AND v_PickedUpTime IS NOT NULL AND v_DoorstepPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_DoorstepPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'DOORSTEP', TIMESTAMPDIFF(SECOND, v_PickedUpTime, v_DoorstepTime) / 60.0
                    );
                END IF;

                IF v_DeliveredTime IS NOT NULL AND v_DeliveryPartner IS NOT NULL THEN
                    INSERT INTO tmp_stage_metrics VALUES (
                        v_CurrentOrderID, v_OrderPIN, v_DeliveryPartner,
                        MONTH(v_PendingTime), YEAR(v_PendingTime),
                        'DELIVER', TIMESTAMPDIFF(SECOND, v_PendingTime, v_DeliveredTime) / 60.0
                    );
                END IF;

            END IF;

            /* Reset local tracking variables */
            SET v_CurrentOrderID = v_OrderID;
            SET v_PendingTime = NULL;
            SET v_OrderPIN = NULL;

            SET v_AcceptPartner = NULL;
            SET v_AcceptedTime = NULL;

            SET v_PickupPartner = NULL;
            SET v_PickedUpTime = NULL;

            SET v_DoorstepPartner = NULL;
            SET v_DoorstepTime = NULL;

            SET v_DeliveryPartner = NULL;
            SET v_DeliveredTime = NULL;

        END IF;

        /* Capture Stage Events & Active Partners */
        IF v_Status = 'PendingAssignment' AND v_PendingTime IS NULL THEN
            SET v_PendingTime = v_Timestamp;
            SET v_OrderPIN = v_PINCode;
        END IF;

        IF v_Status = 'Accepted' AND v_AcceptedTime IS NULL AND v_PendingTime IS NOT NULL THEN
            SET v_AcceptedTime = v_Timestamp;
            SET v_AcceptPartner = v_PartnerID;
        END IF;

        IF v_Status = 'PickedUp' AND v_PickedUpTime IS NULL AND v_AcceptedTime IS NOT NULL THEN
            SET v_PickedUpTime = v_Timestamp;
            SET v_PickupPartner = v_PartnerID;
        END IF;

        IF v_Status = 'ArrivedatDoorStep' AND v_DoorstepTime IS NULL AND v_PickedUpTime IS NOT NULL THEN
            SET v_DoorstepTime = v_Timestamp;
            SET v_DoorstepPartner = v_PartnerID;
        END IF;

        IF v_Status = 'Delivered' AND v_DeliveredTime IS NULL AND v_PendingTime IS NOT NULL THEN
            SET v_DeliveredTime = v_Timestamp;
            SET v_DeliveryPartner = v_PartnerID;
        END IF;

    END LOOP;

    CLOSE cur;

    /* Populate Target Statistics Table */
    INSERT INTO 2026201056_deliverystatistics
    (
        PINCode,
        PartnerID,
        MonthofOrder,
        YearofOrder,

        TotalOrders,
        TotalPendingAssignment,
        TotalAccepted,
        TotalHeadingforPickup,
        TotalArrivedatPickup,
        TotalPickedUp,
        TotalOutforDelivery,
        TotalArrivedatDoorStep,
        TotalDelivered,
        TotalDropped,
        TotalDelayedatPickup,
        TotalDeliveryFailed,
        TotalReturningtoStore,
        TotalReturned,
        TotalCancelled,

        TimetoAccept,
        TimetoPickup,
        TimetoArriveatDoorStep,
        TimetoDeliver
    )
    SELECT
        s.PINCode,
        s.PartnerID,
        MONTH(s.`Timestamp`) AS MonthofOrder,
        YEAR(s.`Timestamp`) AS YearofOrder,

        COUNT(DISTINCT s.OrderID) AS TotalOrders,

        SUM(s.Status = 'PendingAssignment'),
        SUM(s.Status = 'Accepted'),
        SUM(s.Status = 'HeadingforPickup'),
        SUM(s.Status = 'ArrivedatPickup'),
        SUM(s.Status = 'PickedUp'),
        SUM(s.Status = 'OutforDelivery'),
        SUM(s.Status = 'ArrivedatDoorStep'),
        SUM(s.Status = 'Delivered'),
        SUM(s.Status = 'Dropped'),
        SUM(s.Status = 'DelayedatPickup'),
        SUM(s.Status = 'DeliveryFailed'),
        SUM(s.Status = 'ReturningtoStore'),
        SUM(s.Status = 'Returned'),
        SUM(s.Status = 'Cancelled'),

        ROUND(AVG(CASE WHEN m.StageType = 'ACCEPT' THEN m.DurationMinutes END), 2) AS TimetoAccept,
        ROUND(AVG(CASE WHEN m.StageType = 'PICKUP' THEN m.DurationMinutes END), 2) AS TimetoPickup,
        ROUND(AVG(CASE WHEN m.StageType = 'DOORSTEP' THEN m.DurationMinutes END), 2) AS TimetoArriveatDoorStep,
        ROUND(AVG(CASE WHEN m.StageType = 'DELIVER' THEN m.DurationMinutes END), 2) AS TimetoDeliver

    FROM 2026201056_delivery_data_pins_stg s
    LEFT JOIN tmp_stage_metrics m
        ON s.OrderID = m.OrderID
        AND s.PartnerID = m.PartnerID
        AND s.PINCode = m.PINCode
        AND MONTH(s.`Timestamp`) = m.MonthofOrder
        AND YEAR(s.`Timestamp`) = m.YearofOrder
    WHERE s.PartnerID IS NOT NULL AND s.PartnerID <> ''
    GROUP BY
        s.PINCode,
        s.PartnerID,
        MONTH(s.`Timestamp`),
        YEAR(s.`Timestamp`);

    DROP TEMPORARY TABLE IF EXISTS tmp_stage_metrics;

END $$

DELIMITER ;

-- Step 1: Call the procedure to populate data
CALL 2026201056_delivery.PopulateDeliveryStatistics();

-- Step 2: Query the final group count
SELECT COUNT(*) AS NumberOfGroups
FROM 2026201056_deliverystatistics;


USE 2026201056_delivery;

DROP TABLE IF EXISTS 2026201056_requestorstatistics;

CREATE TABLE 2026201056_requestorstatistics (
    RequestorID VARCHAR(255) NOT NULL,
    MonthofOrder INT NOT NULL,
    YearofOrder INT NOT NULL,

    TotalOrdersPlaced INT DEFAULT 0,
    TotalDelivered INT DEFAULT 0,
    TotalCancelled INT DEFAULT 0,
    TotalDeliveryFailed INT DEFAULT 0,

    CancellationRate DECIMAL(5,2) DEFAULT 0.00,
    FailureRate DECIMAL(5,2) DEFAULT 0.00,

    AvgTimeToDeliver DECIMAL(10,2) DEFAULT NULL,
    MostUsedPIN INT DEFAULT NULL,
    MostFrequentPartnerID VARCHAR(255) DEFAULT NULL,

    PRIMARY KEY (RequestorID, MonthofOrder, YearofOrder)
);

/*  RequestorStatistics */


USE 2026201056_delivery;

DELIMITER $$

DROP PROCEDURE IF EXISTS PopulateRequestorStatistics $$

CREATE PROCEDURE PopulateRequestorStatistics()
BEGIN

    /* 1. Truncate target table */
    TRUNCATE TABLE 2026201056_requestorstatistics;

    /* 2. Order-Level Aggregations */
    DROP TEMPORARY TABLE IF EXISTS tmp_requestor_orders;

    CREATE TEMPORARY TABLE tmp_requestor_orders AS
    SELECT 
        OrderRequestorID AS RequestorID,
        OrderID,
        MONTH(MIN(`Timestamp`)) AS MonthofOrder,
        YEAR(MIN(`Timestamp`)) AS YearofOrder,
        
        MIN(PINCode) AS PINCode,

        MAX(CASE WHEN Status = 'Delivered' THEN 1 ELSE 0 END) AS IsDelivered,
        MAX(CASE WHEN Status = 'Cancelled' THEN 1 ELSE 0 END) AS IsCancelled,
        MAX(CASE WHEN Status = 'DeliveryFailed' THEN 1 ELSE 0 END) AS IsFailed,

        MAX(CASE WHEN Status = 'Delivered' AND PartnerID IS NOT NULL AND TRIM(PartnerID) <> '' THEN PartnerID END) AS DeliveringPartner,

        CASE 
            WHEN MAX(CASE WHEN Status = 'Delivered' THEN `Timestamp` END) IS NOT NULL
                 AND MIN(CASE WHEN Status = 'PendingAssignment' THEN `Timestamp` END) IS NOT NULL
            THEN TIMESTAMPDIFF(SECOND, 
                    MIN(CASE WHEN Status = 'PendingAssignment' THEN `Timestamp` END), 
                    MAX(CASE WHEN Status = 'Delivered' THEN `Timestamp` END)
                 ) / 60.0
            ELSE NULL
        END AS TimeToDeliverMinutes

    FROM 2026201056_delivery_data_pins_stg
    WHERE OrderRequestorID IS NOT NULL AND TRIM(OrderRequestorID) <> ''
    GROUP BY OrderRequestorID, OrderID;


    /* 3. Pre-compute Most Used PIN */
    DROP TEMPORARY TABLE IF EXISTS tmp_pin_mode;

    CREATE TEMPORARY TABLE tmp_pin_mode AS
    SELECT RequestorID, MonthofOrder, YearofOrder, PINCode
    FROM (
        SELECT 
            RequestorID,
            MonthofOrder,
            YearofOrder,
            PINCode,
            ROW_NUMBER() OVER (
                PARTITION BY RequestorID, MonthofOrder, YearofOrder 
                ORDER BY COUNT(*) DESC
            ) as rn
        FROM tmp_requestor_orders
        GROUP BY RequestorID, MonthofOrder, YearofOrder, PINCode
    ) ranked_pins
    WHERE rn = 1;


    /* 4. Pre-compute Most Frequent Partner */
    DROP TEMPORARY TABLE IF EXISTS tmp_partner_mode;

    CREATE TEMPORARY TABLE tmp_partner_mode AS
    SELECT RequestorID, MonthofOrder, YearofOrder, DeliveringPartner
    FROM (
        SELECT 
            RequestorID,
            MonthofOrder,
            YearofOrder,
            DeliveringPartner,
            ROW_NUMBER() OVER (
                PARTITION BY RequestorID, MonthofOrder, YearofOrder 
                ORDER BY COUNT(*) DESC
            ) as rn
        FROM tmp_requestor_orders
        WHERE DeliveringPartner IS NOT NULL
        GROUP BY RequestorID, MonthofOrder, YearofOrder, DeliveringPartner
    ) ranked_partners
    WHERE rn = 1;


    /* 5. Populate Final Target Table */
    INSERT INTO 2026201056_requestorstatistics (
        RequestorID,
        MonthofOrder,
        YearofOrder,
        TotalOrdersPlaced,
        TotalDelivered,
        TotalCancelled,
        TotalDeliveryFailed,
        CancellationRate,
        FailureRate,
        AvgTimeToDeliver,
        MostUsedPIN,
        MostFrequentPartnerID
    )
    SELECT 
        o.RequestorID,
        o.MonthofOrder,
        o.YearofOrder,

        COUNT(DISTINCT o.OrderID) AS TotalOrdersPlaced,
        SUM(o.IsDelivered) AS TotalDelivered,
        SUM(o.IsCancelled) AS TotalCancelled,
        SUM(o.IsFailed) AS TotalDeliveryFailed,

        ROUND((SUM(o.IsCancelled) / COUNT(DISTINCT o.OrderID)) * 100, 2) AS CancellationRate,
        ROUND((SUM(o.IsFailed) / COUNT(DISTINCT o.OrderID)) * 100, 2) AS FailureRate,

        ROUND(AVG(o.TimeToDeliverMinutes), 2) AS AvgTimeToDeliver,

        pm.PINCode AS MostUsedPIN,
        ptm.DeliveringPartner AS MostFrequentPartnerID

    FROM tmp_requestor_orders o
    LEFT JOIN tmp_pin_mode pm
        ON o.RequestorID = pm.RequestorID 
       AND o.MonthofOrder = pm.MonthofOrder 
       AND o.YearofOrder = pm.YearofOrder
    LEFT JOIN tmp_partner_mode ptm
        ON o.RequestorID = ptm.RequestorID 
       AND o.MonthofOrder = ptm.MonthofOrder 
       AND o.YearofOrder = ptm.YearofOrder
    GROUP BY 
        o.RequestorID, 
        o.MonthofOrder, 
        o.YearofOrder,
        pm.PINCode,
        ptm.DeliveringPartner;

    /* Clean temporary tables */
    DROP TEMPORARY TABLE IF EXISTS tmp_requestor_orders;
    DROP TEMPORARY TABLE IF EXISTS tmp_pin_mode;
    DROP TEMPORARY TABLE IF EXISTS tmp_partner_mode;

END $$

DELIMITER ;



CALL PopulateRequestorStatistics();


SELECT COUNT(*) AS TotalRequestorGroups
FROM 2026201056_requestorstatistics;


SELECT 
    RequestorID,
    MonthofOrder,
    YearofOrder,
    TotalOrdersPlaced,
    TotalDelivered,
    TotalCancelled,
    CancellationRate,
    FailureRate,
    AvgTimeToDeliver,
    MostUsedPIN,
    MostFrequentPartnerID
FROM 2026201056_requestorstatistics
ORDER BY TotalOrdersPlaced DESC
LIMIT 10;

