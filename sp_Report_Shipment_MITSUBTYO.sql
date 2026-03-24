ALTER PROCEDURE sp_Report_Shipment_MITSUBTYO
    @CurrentCountry CHAR(2),
    @CompanyPK uniqueidentifier,
    @TransportMode VARCHAR(255),
    @JobDateFrom DATETIME,
    @JobDateTo DATETIME,    
    @FirstLoadETDFrom DATETIME,
    @FirstLoadETDTo DATETIME,
    @LastDischargeETAFrom DATETIME,
    @LastDischargeETATo DATETIME,
    @JobType VARCHAR(255)

AS
BEGIN
    SET NOCOUNT ON;

    WITH Base AS (
        SELECT
            JS.JS_UniqueConsignRef AS ShipmentID,
            JK.JK_PK AS JK_PK,
            JK.JK_UniqueConsignRef AS ConsolID,
            MCT.JW_RL_NKLoadPort AS POL,
            RN_POL.RN_Desc AS POLCountry,
            MCT.JW_RL_NKDiscPort AS POD,
            RN_POD.RN_Desc AS PODCountry,
            Carrier.OH_FullName AS ShippingLine,
            JS.JS_HouseBill AS HBL,
            JK.JK_MasterBillNum AS MBL,
            JK.JK_TransportMode AS OceanFreight,
            Debtor.BillingTo AS BillingTo

        FROM dbo.csfn_JobShipmentsWithDirectionCompanyBased(@CurrentCountry, @CompanyPK) JS
            LEFT JOIN dbo.csfn_ShipmentMainConsol(@CurrentCountry) SCL
                ON SCL.JS_PK = JS.JS_PK
            LEFT JOIN dbo.JobConsol JK
                ON JK.JK_PK = SCL.JK_PK
            LEFT JOIN dbo.csfn_MainConsolTransport(@CurrentCountry) MCT
                ON MCT.JW_JK = JK.JK_PK
            LEFT JOIN dbo.ViewFirstLastConsolTransport FLCT
                ON FLCT.ParentType = 'CON'
                AND FLCT.JK = JK.JK_PK
            /*LEFT JOIN dbo.JobContainer JC
                ON JC.JC_JK = JK.JK_PK
            LEFT JOIN dbo.RefContainer RC
                ON RC.RC_PK = JC.JC_RC
            LEFT JOIN dbo.JobContainerPackPivot J6
                ON J6.J6_JC = JC.JC_PK
            LEFT JOIN dbo.JobPackLines JL
                ON JL.JL_PK = J6.J6_JL*/
            LEFT JOIN dbo.RefUNLOCO RL_POL
                ON RL_POL.RL_Code = MCT.JW_RL_NKLoadPort    
            LEFT JOIN dbo.RefCountry RN_POL
                ON RN_POL.RN_Code = RL_POL.RL_RN_NKCountryCode
            LEFT JOIN dbo.RefUNLOCO RL_POD
                ON RL_POD.RL_Code = MCT.JW_RL_NKDiscPort    
            LEFT JOIN dbo.RefCountry RN_POD
                ON RN_POD.RN_Code = RL_POD.RL_RN_NKCountryCode                  
            LEFT JOIN dbo.ctfn_JobShipmentOrg('CRD') Consignor
                ON Consignor.JS_PK = JS.JS_PK
            LEFT JOIN dbo.ctfn_JobShipmentOrg('CED') Consignee
                ON Consignee.JS_PK = JS.JS_PK
            LEFT JOIN dbo.OrgAddress CarrierAddr
                ON CarrierAddr.OA_PK = JK.JK_OA_ShippingLineAddress
            LEFT JOIN dbo.OrgHeader Carrier
                ON Carrier.OH_PK = CarrierAddr.OA_OH
            LEFT JOIN dbo.JobHeader JH
                ON JH.JH_ParentTableCode = 'JS'
                AND JH.JH_ParentID = JS.JS_PK
                AND JH.JH_GC = @CompanyPK
                AND JH.JH_IsActive = 1
            LEFT JOIN dbo.csfn_JobConsolWithDirectionCompanyBased(@CurrentCountry, @CompanyPK) AS JW
                ON JW.JK_PK = JK.JK_PK
            LEFT JOIN (
                SELECT D3_JH, MAX(D3_RecognitionDate) AS D3_RecognitionDate
                FROM dbo.JobChargeRevRecognition
                GROUP BY D3_JH
            ) D3 ON D3.D3_JH = JH.JH_PK
            CROSS APPLY (
                SELECT JS_JobDate =
                    CASE
                        WHEN D3.D3_RecognitionDate IS NULL THEN
                            CASE WHEN JW.JK_Direction = 'IMP'
                                THEN FLCT.LastDischarge_ETA
                                ELSE FLCT.FirstLoad_ETD
                            END
                        WHEN MONTH(
                                CASE WHEN JW.JK_Direction = 'IMP'
                                    THEN FLCT.LastDischarge_ETA
                                    ELSE FLCT.FirstLoad_ETD
                                END
                            ) = MONTH(D3.D3_RecognitionDate)
                        THEN
                            CASE WHEN JW.JK_Direction = 'IMP'
                                THEN FLCT.LastDischarge_ETA
                                ELSE FLCT.FirstLoad_ETD
                            END
                        ELSE D3.D3_RecognitionDate
                    END
            ) JD
            OUTER APPLY (
                SELECT
                    MAX(Debtor.OH_FullName) AS BillingTo
                FROM JobCharge JR
                LEFT JOIN JobHeader JH
                    ON JH.JH_PK = JR.JR_JH
                LEFT JOIN JobShipment JS2
                    ON JS2.JS_PK = JH.JH_ParentID
                LEFT JOIN JobConShipLink JN
                    ON JN.JN_JS = JS2.JS_PK
                LEFT JOIN JobConsol JK2
                    ON JK2.JK_PK = JN.JN_JK
                LEFT JOIN OrgHeader Debtor
                    ON Debtor.OH_PK = JR.JR_OH_SellAccount
                WHERE JK2.JK_PK = JK.JK_PK 
            ) Debtor

        WHERE
            /*JC.JC_ContainerNum IS NOT NULL
            NULLIF(LTRIM(RTRIM(RC.RC_Code)), '') IS NOT NULL*/
            (@TransportMode = '' OR JS.JS_TransportMode = @TransportMode)
            AND
            (
                (FLCT.FirstLoad_ETD IS NOT NULL
                    AND (@FirstLoadETDFrom IS NULL OR FLCT.FirstLoad_ETD >= @FirstLoadETDFrom)
                    AND (@FirstLoadETDTo   IS NULL OR FLCT.FirstLoad_ETD < @FirstLoadETDTo)
                )
                OR (@FirstLoadETDFrom IS NULL AND @FirstLoadETDTo IS NULL)
            )

            AND
            (
                (FLCT.LastDischarge_ETA IS NOT NULL
                    AND (@LastDischargeETAFrom IS NULL OR FLCT.LastDischarge_ETA >= @LastDischargeETAFrom)
                    AND (@LastDischargeETATo   IS NULL OR FLCT.LastDischarge_ETA < @LastDischargeETATo)
                )
                OR (@LastDischargeETAFrom IS NULL AND @LastDischargeETATo IS NULL)
            )

            AND
            (
                (NULLIF(@JobDateFrom,'') IS NULL OR @JobDateFrom = '' OR JD.JS_JobDate >= @JobDateFrom)
                AND
                (NULLIF(@JobDateTo,'')   IS NULL OR @JobDateTo   = ''
                    OR JD.JS_JobDate < DATEADD(DAY, 1, CONVERT(date, @JobDateTo)))
            )
            AND
            (
                @JobType IS NULL
                OR @JobType = ''
                OR @JobType = 'ALL JOB'
                OR (@JobType = 'MITSUBTYO Job' AND Consignor.OH_Code = 'MITSUBTYO')
            )
    ),

    ContainerAgg AS (
        SELECT
            JC.JC_JK AS JK_PK,

            SUM(
                CASE 
                    WHEN ISNULL(JC.JC_ContainerCount,0) > 0 
                    THEN JC.JC_ContainerCount 
                    ELSE 1 
                END
            ) AS ContainerCount,

            SUM(
                CASE 
                    WHEN RC.RC_Code LIKE '20%' 
                    THEN (CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END) * 1

                    WHEN RC.RC_Code LIKE '40%' 
                    THEN (CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END) * 2

                    WHEN RC.RC_Code LIKE '45%' 
                    THEN (CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END) * 2

                    ELSE 0
                END
            ) AS TEU,            

            SUM(
                CASE 
                    WHEN RC.RC_Code LIKE '20%' 
                    THEN CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END
                    ELSE NULL
                END
            ) AS Container20,

            SUM(
                CASE 
                    WHEN RC.RC_Code LIKE '40%' 
                    THEN CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END
                    ELSE NULL
                END
            ) AS Container40,

            SUM(
                CASE 
                    WHEN RC.RC_Code LIKE '45%' 
                    THEN CASE WHEN ISNULL(JC.JC_ContainerCount,0) > 0 THEN JC.JC_ContainerCount ELSE 1 END
                    ELSE NULL
                END
            ) AS Container45           

        FROM dbo.JobContainer JC
        LEFT JOIN dbo.RefContainer RC ON RC.RC_PK = JC.JC_RC
        GROUP BY JC.JC_JK
    ),

    Final AS (
        SELECT
            B.ShipmentID,
            B.ConsolID,
            B.POL,
            B.POLCountry,
            B.POD,
            B.PODCountry,
            B.ShippingLine,
            B.OceanFreight,
            B.HBL,
            B.MBL,
            B.BillingTo,

            A.ContainerCount,
            A.TEU,
            A.Container20,
            A.Container40,
            A.Container45

        FROM Base B
        LEFT JOIN ContainerAgg A ON A.JK_PK = B.JK_PK
    )

    SELECT
        ShipmentID,
        ConsolID,
        POL,
        POLCountry,
        POD,
        PODCountry,
        ShippingLine,
        OceanFreight,
        HBL,
        MBL,
        ContainerCount,
        TEU,
        Container20,
        Container40,
        Container45,
        BillingTo
    FROM Final

END