--**************************************************************--
--Please read completely and test on your database.				--
--AutoAudit makes several changes to your tables.				--
--Adding AutoAudit to your tables will impact performance.		--
--Set the variables below to your requirements before executing.--
--**************************************************************--

set nocount on
--USE AutoAudit -- edit for your database


--*******************************************************
--				VARIABLE DECLARATIONS
--*******************************************************
declare @AuditSchema varchar(50),
		@ViewSchema varchar(50),
		@Version varchar(5),
		@OptimizeForAudit bit,
		@DetailedMigrationCheck bit,
		@CreatedColumnName sysname,
		@CreatedByColumnName sysname,
		@ModifiedColumnName sysname,
		@ModifiedByColumnName sysname,
		@RowVersionColumnName sysname,
		@RebuildTriggersAfterInstall bit,
		@WithLogFlag bit,
		@DateStyle varchar(3),
		@ViewPrefix varchar(10),
		@UDFPrefix varchar(10),
		@RowHistoryViewSuffix varchar(20),
		@DeletedViewSuffix varchar(20),
		@RowHistoryFunctionSuffix varchar(20),
		@TableRecoveryFunctionSuffix varchar(20)
	
		
--*******************************************************
--				VARIABLE INITIALIZATION
--*******************************************************
Set @AuditSchema		= 'Audit'			--This is the schema to use for the AutoAudit objects. Edit for your database

Set @ViewSchema			= '<TableSchema>'	--This is the schema to use for the AutoAudit base table views. Edit for your database.
											--<TableSchema> = the _RowHistory and _Deleted views have the same schema as the base table.

Set @Version			= '3.30a'			--leave this unless you are making changes to this script

Set @OptimizeForAudit	= 0					--@OptimizeForAudit = 0 creates an index to speed up views
											--(and slows down AutoAudit), @OptimizeForAudit = 1 keeps AutoAudit 10% faster 
											--but the reporting views are slower.

Set @RebuildTriggersAfterInstall = 1		--@RebuildTriggersAfterInstall = 1 launches pAutoAuditRebuildAll after
											--this script has completed and AutoAudit has been updated
											--@RebuildTriggersAfterInstall = 0 runs this script to update AutoAudit but does NOT 
											--execute pAutoAuditRebuildAll. This may cause problems with your existing AutoAudit
											--triggers views and UDFs.

Set @DetailedMigrationCheck	= 0				--This is only applicable if you are upgrading your AutoAudit environment
											--from version 2.00h to 3.20. The detailed verification could take several minutes to
											--complete.
											--0 = quick check with rowcount only, 1 = detailed record verification

Set @WithLogFlag = 0						--This flag determines if the "With Log" function is included in the raierror 
											--statements or not
											--this is added because some DBA's may not have rights to write to the Windows log
											--0 = exclude "with log", 1 = include "with log"

--set DDL column names
--*** make sure these DO NOT require quotename() (no spaces, special characters etc.)
--*** IF YOU ARE UPGRADING FROM AUTOAUDIT 2.X set the column names to Created, CreatedBy, Modified, ModifiedBy and RowVersion 
--    otherwise the upgrade process will add new columns. 
--    YOU CAN CHANGE THE NAMES LATER IN THE BASE TABLES AND THE AUTOAUDITSETTINGS TABLE.
Set @CreatedColumnName = 'AutoAudit_CreatedDate'
Set @CreatedByColumnName = 'AutoAudit_CreatedBy'
Set @ModifiedColumnName = 'AutoAudit_ModifiedDate'
Set @ModifiedByColumnName = 'AutoAudit_ModifiedBy'
Set @RowVersionColumnName = 'AutoAudit_RowVersion'

Set @DateStyle			= '121'				--this variable identifies the date style you wish to use when inserting data into
											--the AuditHeader table. It is recommended you only use a style that provides full
											--datetime precision with century. These are the tested and allowed choices.
												-- 113 : 26 Nov 2013 13:20:54:553
												-- 121 : 2013-11-26 13:22:55.170
												
--Set object prefixes and suffixes
Set @ViewPrefix = 'v'								--User configurable - sets the PREFIX for _RowHistory, _Deleted views
Set @UDFPrefix = ''									--User configurable - sets the PREFIX for _RowHistory, _TableRecovery functions
Set @RowHistoryViewSuffix = '_RowHistory'			--User configurable - sets the suffix for "_RowHistory" views
Set @DeletedViewSuffix = '_Deleted'					--User configurable - sets the suffix for "_Deleted" views
Set @RowHistoryFunctionSuffix = '_RowHistory'		--User configurable - sets the suffix for "_RowHistory" functions
Set @TableRecoveryFunctionSuffix = '_TableRecovery'	--User configurable - sets the suffix for "_TableRecovery" functions

--*******************************************************
--			END OF VARIABLE INITIALIZATION
--*******************************************************


												
/* 
PLEASE READ NOTES COMPLETELY AND TEST ON YOUR DATABASE.

AUTOAUDIT MAKES SEVERAL CHANGES TO YOUR TABLES. 

----------------------------------
AutoAudit script
for SQL Server 2005, 2008, 2008R2, 2012
(c) 2007-2013 Paul Nielsen Consulting, inc.
www.sqlserverbible.com
AutoAudit.codeplex.com
Created by Paul Nielsen
Coded by Paul Nielsen and John Sigouin

December 2013
Version 3.30a

----------------------------------
executing this script will add the following 
objects to your database:

Tables:
  - <AuditSchema>.AuditHeader (new for 3.00)
  - <AuditSchema>.AuditDetail (new for 3.00)
  - <AuditSchema>.AuditHeaderArchive (new for 3.00)
  - <AuditSchema>.AuditDetailArchive (new for 3.00)
  - <AuditSchema>.AuditSettings (new for 3.00)
  - <AuditSchema>.AuditBaseTables (new for 3.00)
  - <AuditSchema>.AuditAllExclusions (new for 3.00)
  - <AuditSchema>.SchemaAudit

Stored Procedures:
  - <AuditSchema>.pAutoAudit
  - <AuditSchema>.pAutoAutitDrop 
  - <AuditSchema>.pAutoAuditAll
  - <AuditSchema>.pAutoAuditDropAll
  - <AuditSchema>.pAutoAuditArchive (new for 3.00)
  - <AuditSchema>.pAutoAuditRebuild (new for 3.00)
  - <AuditSchema>.pAutoAuditRebuildAll (new for 3.00)

Views:
  - <AuditSchema>.vAudit view (new for 3.00)
  - <AuditSchema>.vAuditArchive view (new for 3.00)
  - <AuditSchema>.vAuditAll view (new for 3.00)
  - <AuditSchema>.vAuditHeaderAll view (new for 3.00)
  - <AuditSchema>.vAuditDetailAll view (new for 3.00)

Database DDL Trigger:
  - SchemaAuditDDLTrigger DDL Trigger 
     (on database for DDL_DATABASE_LEVEL_EVENTS)


----------------------------------
***************************************************************************
***************************************************************************
Important: The 2.00h Audit table is being replaced by a AuditHeader and
           AuditDetail table in version 3.x.
           If you are currently using AutoAudit version 2.00h, running this
           script will automatically create the new tables and migrate all
           of your existing Audit data into the AuditHeader and AuditDetail 
           tables.
           Also, all of your existing AutoAudit base table triggers will be
           rebuild such that at the end of this installation, the system 
           will continue to audit as it used to but save the data to the
           new tables.
           Your current Audit table will be renamed to LegacyAudit_Migrated
           and your current SchemaAudit table will be renamed to 
           dbo.LegacySchemaAudit_Migrated.
           After verifying the installation and migration of your existing 
           Audit data to the new table structure, you should drop the 
           LegacyAudit_Migrated and LegacySchemaAudit_Migrated tables.
           The new vAudit view created during the installation produces a
           recordset identical to what is stored in your current Audit table.

           ****************************************************************
           I am confident the upgrade process works correctly, but because 
           of possible differences in your installation compared to the 
           2.00h baseline installation, it is strongly recommended you 
           backup your database before running this script.
           ****************************************************************
***************************************************************************


***************************************************************************
Features (default behaviors):
Code-gens triggers to records all inserts, updates, and deletes 
into a common generic audit table structure. 

on insert: Records insert event in Audit tables (AuditHeader and AuditDetail) 
  including who made the insert, when, from what application and workstation. 
  The row's Created and CreatedBy columns also
  reflect the user context. 

on update: Records update events in the Audit tables including 
  who, when, from where, and the before and after values. 
  The row's Modified and ModifiedBy columns also store the basic 
  audit data. The update also increments the row's RowVersion column.

On delete: All the final values are written to the audit tables
  while this permits undeleting rows, it is performance intensive 
  when deleting a large number of rows on a wide table.  

----------------------------------
Limitations:

  Does not audit changes of columns of these data types:
  text, ntext, image, geography, xml, binary, varbinary, timestamp,
  rowversion 

  Adding AutoAudit triggers to a table will impact performance, 
  potentially doubling or tripling the normal DML execution times. 
  The width of the table increases the impact of the AutoAudit 
  triggers during updates. 


AutoAudit database object description
--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditHeader Table (new for 3.00)

This table is inserted with one row everytime one record is inserted, 
    updated or deleted in a table that has been setup to use the 
    AutoAudit system.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditDetail Table (new for 3.00)

This table is related to AuditHeader and is inserted with one row 
    for each column that is changed during an insert or update
    operation and for each column during a delete operation.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditHeaderArchive Table (new for 3.00)

This table contains all the rows that originated in the AuditHeader
    table but that have been selected to be archived based on the 
    archival timeframes processed by the 
    <AuditSchema>.pAutoAuditArchive procedure.


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditDetailArchive Table (new for 3.00)

This table contains all the rows that originated in the AuditDetail
    table but that have been selected to be archived based on the 
    archival timeframes processed by the 
    <AuditSchema>.pAutoAuditArchive procedure.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.SchemaAudit Table (modified for 3.00)

This table contains one row for each database DDL event that is 
captured by the SchemaAuditDDLTrigger database trigger.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditSettings Table (new for 3.00)

This table contains a small number of rows that are used to persist
some important settings and parameters that are needed by the 
AutoAudit system.

Important:
	After running this script to install AutoAudit, please review
	the User configurable settings and configure them to your 
    preferences.

Here's a list of entries in the AuditSettings table:
	SettingName:	AuditSchema
	SettingValue:	Audit (default)
	AdditionalInfo: System setting added by AutoAudit installation 
					SQL script.  Do not change manually in the table.

	SettingName:	Schema for _RowHistory _TableRecovery and _Deleted objects
	SettingValue:	<TableSchema> (default)
	AdditionalInfo: User configurable - Schema AutoAudit uses for 
					_RowHistory, _TableRecovery and _Deleted objects.
					Valid entries can be an existing schema or <TableSchema>. 
					The default is <TableSchema>. When <TableSchema>
					is used, the schema of the AutoAudit views for
					with match the schema of each base table.

	SettingName:	Version
	SettingValue:	3.00 (current value)
	AdditionalInfo: System setting added by AutoAudit installation 
					SQL script.  Do not change manually in the table.

	SettingName:	SchemaAuditDDLTrigger Enabled Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable - Immediate change. No action 
					required.  0 = DDL trigger disabled, 1 = DDL 
					trigger enabled.

	SettingName:	Archive Audit data older than (days)
	SettingValue:	30 (default)
	AdditionalInfo: User configurable - Immediate change. No action 
					required.  Audit data older than this number of 
					days will be moved to the archive tables when the 
					pAutoAuditArchive stored procedure is executed.

	SettingName:	Delete Audit data older than (days)
	SettingValue:	365 (default)
	AdditionalInfo: User configurable - Immediate change. No action 
					required.  Audit data older than this number of 
					days will be deleted permanently when the 
					pAutoAuditArchive stored procedure is executed.

	SettingName:	RowHistory View Scope
	SettingValue:	Active (default)
	AdditionalInfo: User configurable - Must execute pAutoAuditRebuild(All) 
					or pAutoAudit(All) to apply change. Determines 
					source of data when _RowHistory views are created. 
					Valid entries are: "Active", "Archive", "All".

	SettingName:	Deleted View Scope
	SettingValue:	Active (default)
	AdditionalInfo: User configurable - Must execute pAutoAuditRebuild(All) 
					or pAutoAudit(All) to apply change. Determines 
					source of data when _Deleted views are created. 
					Valid entries are: "Active", "Archive", "All".

	SettingName:	Default _RowHistory view Creation Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable
					0 = _RowHistory view is not created, 
					1 = _RowHistory view is created.

	SettingName:	Default _RowHistory function Creation Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable
                    0 = _RowHistory function is not created, 
					1 = _RowHistory function is created.

	SettingName:	Default _TableRecovery function Creation Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable
                    0 = _TableRecovery function is not created, 
					1 = _TableRecovery function is created.

	SettingName:	Default _Deleted view Creation Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable
					0 = _Deleted view is not created, 
					1 = _Deleted view is created.

	SettingName:	Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag
	SettingValue:	1 (default)
	AdditionalInfo: System setting added by AutoAudit installation 
					SQL script.  Do not change manually in the table.

	SettingName:	Audit Trigger Debug Flag
	SettingValue:	0 (default)
	AdditionalInfo: User configurable
                    0 = Debug information (The trigger name and nest level) in returned
                        by the AutoAudit Insert, Update and Delete triggers.
					1 = Debug information is not returned

	SettingName:	Add Extended Properties Flag
	SettingValue:	1 (default)
	AdditionalInfo: User configurable
                    0 = Extended properties are not added.
					1 = Extended properties are not added on DDL columns under the
						MS_Decription name

	SettingName:	CreatedColumnName
	SettingValue:	AutoAudit_Created (default)
	AdditionalInfo: User Configurable - Sets the column name of the column that is added
					to the base tables to save the "record creation date" entry by AutoAudit
					when "@BaseTableDDL = 1" is set in the execution of pAutoAudit.

	SettingName:	CreatedByColumnName
	SettingValue:	AutoAudit_CreatedBy (default)
	AdditionalInfo: User Configurable - Sets the column name of the column that is added
					to the base tables to save the "record created by" entry by AutoAudit
					when "@BaseTableDDL = 1" is set in the execution of pAutoAudit.

	SettingName:	ModifiedColumnName
	SettingValue:	AutoAudit_Modified (default)
	AdditionalInfo: User Configurable - Sets the column name of the column that is added
					to the base tables to save the "record last modifocation date" entry
					by AutoAudit when "@BaseTableDDL = 1" is set in the execution of pAutoAudit.

	SettingName:	ModifiedByColumnName
	SettingValue:	AutoAudit_ModifiedBy (default)
	AdditionalInfo: User Configurable - Sets the column name of the column that is added
					to the base tables to save the "record last modified by" entry by AutoAudit
					when "@BaseTableDDL = 1" is set in the execution of pAutoAudit.

	SettingName:	RowVersionColumnName
	SettingValue:	AutoAudit_RowVersion (default)
	AdditionalInfo: User Configurable - Sets the column name of the column that is added
					to the base tables to save the "record verion number" entry by AutoAudit
					when "@BaseTableDDL = 1" is set in the execution of pAutoAudit.

	SettingName:	ViewPrefix
	SettingValue:	v (default)
	AdditionalInfo:	User configurable (default = "v") - Must execute pAutoAuditRebuild(All) or 
					pAutoAudit(All) to apply change. Sets the prefix to use for the _RowHistory 
					and _Deleted views.

	SettingName:	DateStyle
	SettingValue:	121 (default)
	AdditionalInfo:	System setting added by AutoAudit installation SQL script. Do not change 
					manually in the table. You can re-run the AutoAudit installation script to 
					change this setting.

	SettingName:	UDFPrefix
	SettingValue:	'' (default)
	AdditionalInfo:	User configurable (default = "") - Must execute pAutoAuditRebuild(All) or 
					pAutoAudit(All) to apply change. Sets the prefix to use for the _RowHistory 
					and _TableRecovery views.

	SettingName:	RowHistoryViewSuffix
	SettingValue:	_RowHistory (default)
	AdditionalInfo:	User configurable (default = "_RowHistory") - Must execute 
					pAutoAuditRebuild(All)  or pAutoAudit(All) to apply change. Sets the suffix 
					to use for the _RowHistory views.

	SettingName:	DeletedViewSuffix
	SettingValue:	_Deleted (default)
	AdditionalInfo:	User configurable (default = "_Deleted") - Must execute pAutoAuditRebuild(All) 
					or pAutoAudit(All) to apply change. Sets the suffix to use for the _Deleted 
					views.

	SettingName:	RowHistoryFunctionSuffix
	SettingValue:	_RowHistory (default)
	AdditionalInfo:	User configurable (default = "_RowHistory") - Must execute 
					pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to 
					use for the _RowHistory functions.

	SettingName:	TableRecoveryFunctionSuffix
	SettingValue:	_TableRecovery (default)
	AdditionalInfo:	User configurable (default = "_TableRecovery") - Must execute 
					pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to 
					use for the _TableRecovery functions.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditBaseTables Table (new for 3.00)

This table contains one row for each of the base tables that was 
    setup to use the AutoAudit system.  The data in this table can
    be useful for a DBA who wants to review which base tables are
    setup for Auto 
Changes to the AutoAudit configuration for each table can be done in 
    this table.
The pAutoAuditRebuild stored procedure is dependant on the data in 
    this table to work.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.AuditAllExclusions Table (new for 3.00)

This table contains a user-defined list or base tables to exclude 
    when the pAutoAuditAll stored procedure is executed.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.vAudit view (new for 3.00)

This view retrieves data from AuditHeader and AuditDetail to produce
    a recordset with the same structure as the Audit table had in 
    Version 2.00h.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.vAuditArchive view (new for 3.00)

This view retrieves data from AuditHeaderArchive and 
    AuditDetailArchive to produce a recordset with the same structure 
    as the Audit table had in Version 2.00h.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.vAuditAll view (new for 3.00)

This view does a Union All of the data from the vAudit and 
    vAuditArchive tables. In essence this is a view to all the data
    contained in the AutoAudit (Active and Archive) tables.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.vAuditHeaderAll view (new for 3.00)

This view does a Union All of the data from the AuditHeader and 
    AuditHeaderArchive tables. In essence this is a view to all the 
    header data contained in the AutoAudit (Active and Archive) 
    tables.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.vAuditDetailAll view (new for 3.00)

This view does a Union All of the data from the AuditdDetail and 
    AuditDetailArchive tables. In essence this is a view to all the 
    detail data contained in the AutoAudit (Active and Archive) 
    tables.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAudit Procedure

applies AutoAudit to a single table

parameters: 
  @SchemaName sysname - the schema of the table (default = 'dbo') 
  @TableName sysname - the name of the table (required)
     (sysname is NVARCHAR(128))
  
  @StrictUserContext BIT (default = 1)
  @LogSQL BIT (Default = 0)
  @BaseTableDDL BIT (Default = 0)
  @LogInsert TINYINT (Default = 2)    
  @LogUpdate TINYINT (Default = 2)    
  @LogDelete TINYINT (Default = 2)    

---
pAutoAudit will make the following changes:

  add columns: Created, CreatedBy, Modified, ModifiedBy, 
               and RowVersion if @BaseTableDDL = 1
  add triggers: tablename_Audit_Insert, tablename_Audit_Update, 
                tablename_Audit_Delete
  add views: <AuditViewSchema>.vtablename_Deleted,
              <AuditViewSchema>.vtablename_RowHistory
  add function: <AuditViewSchema>.tablename_RowHistory,
				<AuditViewSchema>.tablename_TableRecovery

---
Options: 

@StrictUserContext determines how user context columns are set
      (user - CreatedBy and ModifiedBy, audit time - Created 
       and Modified)  
    1 = (default) user context set by server login - suser_sname() 
        and server time (GetDate())
    0 = user context default to server values, but can be determined 
        by DML and are nullable. 
    
    When using @StrictUserContext = 0: 
      Insert: an insert DML statement can insert into the Created 
              and CreatedBy columns. 
      Update: an update DML statement can freely update the Created, 
              CreatedBy, Modified, and ModifiedBy columns.
      Delete: delete DML statements do not include dml columns, so when 
              the @StrictUserContext is set to 0, the previous modified 
              and modified values are captured into the audit trail table. 
              To record the correct delete user and datetime, first touch 
              (update) the row's Modified and/or ModifiedBy columns.  
      
    For most applications leaving @StrictUserContext on is approriate. 
    Turning @StrictUserContext off is useful for two use cases: 
       1 - applications that manage their own user security and log into 
           SQL Server using a common security context. These applications 
           can pass the user name to AutoAudit by inserting into the base 
           table's CreatedBy column or updating the base table's Modified 
           column. 
       2 - when importing data from a previous database that already has
           legacy audit data. 
       
    The StrictUserContext = 0 requires the BaseTableDDL option enabled, 
        since the CreatedBy and ModifiedBy columns are used to pass in 
        the user context. 

---
@LogSQL determines if the SQL batch that fired the event is logged

    1 = the SQL Batch is logged in the SQLStatement column
    0 = (default) the SQL Batch is not logged
    
SQL logging is useful for debugging, however, it can **severely** BlOaT the 
audit log, so it should be normally set off (or the storage team will laugh 
at you when your 6 Gb database grows to 115Gb in a week ;-)  

--- 
@BaseTableDDL determines if the Created, CreatedBy, Modified, ModifiedBy 
and RowVersion columns are added to the base tables    
    0 = make no changes to the base tables
    1 = (default) add the Created, CreatedBy, Modified, ModifiedBy, and 
        RowVersion columns to the base tables

Adding the Created, Modified, and RowVersion columns is appropriate for 
   most tables. However, some third party databases do not allow modifying 
   the base table. 
   
---
@LogInsert determines how much is logged to the audit trail on an insert 
    event. 
    0 - Nothing is logged to the audit trail tables. This is useful for 
        importing data and avoiding a false insert event in the Audit table.
        When not loggin the insert, you can still get the inserted datetime
        from the Created column and the update event will have the old value. 
    1 - The insert event is written to the AuditHeader table 
    2 - (default) The AuditHeader is written and all columns are written 
        to the AuditDetail table.

@LogUpdate determines how much is logged to the audit trail on an insert 
    event. 
    0 - Nothing is logged to the audit trail tables. *** Use this option with 
        caution! You will not be able to re-create your data at a point in 
        time with this setting.
    1 - The update event is written to the AuditHeader table. *** Use this option  
        with caution! You will not be able to re-create your data at a point in 
        time with this setting. 
    2 - (default) The AuditHeader is written and all updated columns are   
        written to the AuditDetail table.

@LogDelete determines how much is logged to the audit trail on an insert 
    event. 
    0 - Nothing is logged to the audit trail tables. *** Use this option with 
        caution! You will not be able to re-create your data at a point in 
        time with this setting.
    1 - The insert event is written to the AuditHeader table. *** Use this option  
        with caution! You will not be able to re-create your data at a point in 
        time with this setting.
    2 - (default) The AuditHeader is written and all columns are written 
        to the AuditDetail table.

Regardless of the @LogInsert and @LogUpdate setting, the Created, CreatedBy,  
   Modified, ModifiedBy, and RowVersion columns on the base table are always 
   set if AutoAudit was added to the table with option @BaseTableDDL = 1. 

---

To change the options for a table, simply re-exec the pAutoAudit proc  
    with the required options to re-generate the triggers for the table.
    Alternatively, you can update the AutoAudit settings changes on a
    table by table basis in the <AuditSchema>.AuditBaseTables table
    and then execute <AuditSchema>.pAutoAuditRebuild or
    <AuditSchema>.pAutoAuditRebuildAll.

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditAll Procedure

Executes pAutoAudit for every basetable except for the tables listed
in the <AuditSchema>.AuditAllExclusions table.

parameters: 
  @StrictUserContext BIT (default = 1)
  @LogSQL BIT (Default = 0)
  @BaseTableDDL BIT (Default = 0)
  @LogInsert TINYINT (Default = 2)    
  @LogUpdate TINYINT (Default = 2)    
  @LogDelete TINYINT (Default = 2)    


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditDrop Procedure

Removes columns, triggers, views, and function 
created by pAutoAudit for a single table. 

parameters: 
  @SchemaName sysname - the schema of the table (default = 'dbo') 
  @TableName sysname - the name of the table (required)
    (sysname is NVARCHAR(128))
  @DropBaseTableDDLColumns  BIT (Default = 1)
    0 = keeps the base table DDL columns
    1 = (default) drops the base table DDL columns
  @DropBaseTableTriggers BIT (Default = 1)
    0 = keeps the base table AutoAudit Triggers
    1 = (default) drops the base table AutoAudit Triggers
  @DropBaseTableViews BIT (Default = 1)
    0 = keeps the base table AutoAudit views and function
    1 = (default) drops the base table AutoAudit views and function

It does not remove the audit tables or SchemaAudit 
trigger or table created when this script is executed 
in a database.

If your intention is to keep the AutoAudit triggers but drop the
DDL columns, you will also have to use <AuditSchema>.pAutoAuditRebuild

--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditDropAll Procedure

Drops selected components of Auto
Optionally executes pAutoAuditDrop for every basetable using the 
   default options.

parameters: 
  @DropAuditTables BIT (Default = 0)
    0 = (default) keeps the AutoAudit tables
    1 = drops all the AutoAudit tables
  @DropAuditViews BIT (Default = 0)
    0 = (default) keeps the AutoAudit views
    1 = drops all the AutoAudit views
  @DropAuditSPs BIT (Default = 0)
    0 = (default) keeps the AutoAudit SP's
    1 = drops all the AutoAudit SP's
  @DropAuditDDLTriggers BIT (Default = 0)
    0 = (default) keeps the AutoAudit DDL Trigger
    1 = drops the AutoAudit DDL Trigger
  @DropBaseTableDDLColumns BIT (Default = 0)
    0 = (default) keeps the base table DDL columns
    1 = drops the base table DDL columns 
         from each base table
  @DropBaseTableTriggers BIT (Default = 0)
    0 = (default) keeps the base table AutoAudit Triggers
    1 = drops the base table AutoAudit Triggers 
         from each base table
  @DropBaseTableViews BIT (Default = 0)
    0 = (default) keeps the base table AutoAudit views and function
    1 = drops the base table AutoAudit views and function
  @ConfirmAllDrop varchar(10) (Default = 'no')
    'no' = (default) Does not proceed with the AllDrop SP
    'yes' = proceeds with the AllDrop SP

Important: 
If @DropAuditTables=1 then @DropAuditViews, @DropBaseTableTriggers,
   @DropAuditSPs, @DropBaseTableViews and @DropAuditDDLTriggers 
   are forced to 1

When @DropAuditTables, @DropAuditViews or @DropAuditSPs
   are flaged as 1, pAutoAuditDropAll removes AutoAudit components
   from the database.  Depending on the options the schema audit 
   DDL trigger and table, and the Audit tables will be removed. 


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditRebuild Procedure (new for 3.00)

Drops and re-creates the Audit base table triggers, views and 
function.  The re-created components use the settings from the 
<AuditSchema>.AuditBaseTables table for the specified based table.  

This AuditBaseTables table and pAutoAuditRebuild sp can be very 
useful if columns have been added/modified in a base table. If 
you need to make AutoAudit settings changes to one or more 
tables all you need to do is change entries in the AuditBaseTables
table.  If a column is added to a base table and needs to be included
in the AuditDetail list of columns, add the column name to the 
ColumnNames value for that base table before rebuilding the AutoAudit
objects. For example if you want to remove SQL statement loging on
all base tables, you can update that flag for all records and simply
execute the pAutoAuditRebuild or pAutoAuditRebuildAll procedure.

parameters: 
  @SchemaName sysname - the schema of the table (default = 'dbo') 
  @TableName sysname - the name of the table (required)

Important:
If "Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag"
    is set to 1 in the <AuditSchema>.AuditSettings table, when the 
    SchemaAuditDDLTrigger database DDL trigger fires due to a base
    table schema change, SchemaAuditDDLTrigger makes an automagic
    call to pAutoAuditRebuild after a ALTER_TABLE event.


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditRebuildAll Procedure (new for 3.00)

Executes pAutoAuditRebuild for every basetable that has  an entry 
  in the <AuditSchema>.AuditBaseTables table.

parameters: 
   <none>


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditArchive Procedure

Moves a portion of the data from the AuditHeader and AuditDetail
tables to the AuditHeaderArchive and AuditDetailArchive tables
and/or deletes Audit data permanently.
This stored procedure should be executed on a regular basis
(with SSA) to keep the live Audit tables to a reasonable size and
performance level.

 parameters: 
  @ArchiveAfterNumberOfDays int = -1 
     The number of days after which the audit data will be moved
     to the Archive table. If -1 is entered, then the setting from 
     the <AuditSchema>.AuditSettings table will be used.
  @DeleteAfterNumberOfDays int = -1 
     The number of days after which the audit data will be permanently
     deleted from the archive (or active) Audit tables. If -1 is 
     entered, then the setting from the <AuditSchema>.AuditSettings 
     table will be used.
  @KeepLastEntry bit = 1
    0 = keeps the base table AutoAudit views and function
    1 = (default) The last Audit entry for each primary key is not 
        archived (even if it should based on dates) to ensure a 
        sequential RowVersion is produced when logging future changes.

Important: 
It is recommended to leave @KeepLastEntry bit = 1 when you did not
   add the DDL columns to the base table otherwise you may
   end-up with multiple Audit entries with the same RowVersion.

@DeleteAfterNumberOfDays must be >= @ArchiveAfterNumberOfDays


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditSetTriggerState Procedure (new for 3.02)

Enables or disables AutoAudit triggers at the SQL Server level.  

This is different from the EnabledFlag entry in the AuditBaseTables
tables. The pAutoAuditSetTriggerState SP enables or disables the 
triggers at the SQL Server level where the EnabledFlag entry in the 
AuditBaseTables table keeps the triggers enabled but makes the
AutoAudit exit before logging the Audit event.

parameters: 
  @SchemaName sysname - the schema of the table (default = 'dbo') 
  @TableName sysname - the name of the table (required)
  @InsertEnabledFlag BIT = 1  (Default = 1)
     1 = the insert trigger is enabled
     0 = the insert trigger is disabled
  @UpdateEnabledFlag BIT = 1  (Default = 1)
     1 = the update trigger is enabled
     0 = the update trigger is disabled
  @DeleteEnabledFlag BIT = 1  (Default = 1)
     1 = the delete trigger is enabled
     0 = the delete trigger is disabled


--------------------------------------------------------------------
--------------------------------------------------------------------
* <AuditSchema>.pAutoAuditSetTriggerStateAll Procedure (new for 3.02)

Executes pAutoAuditSetTriggerState for every basetable that has  an entry 
  in the <AuditSchema>.AuditBaseTables table.

parameters: 
  @InsertEnabledFlag BIT = 1  (Default = 1)
     1 = the insert trigger is enabled
     0 = the insert trigger is disabled
  @UpdateEnabledFlag BIT = 1  (Default = 1)
     1 = the update trigger is enabled
     0 = the update trigger is disabled
  @DeleteEnabledFlag BIT = 1  (Default = 1)
     1 = the delete trigger is enabled
     0 = the delete trigger is disabled


-----------------------------------------------------------------
-----------------------------------------------------------------
Development Change History

-----------------------------------
version 1.01 - Jan 15, 2007
   added RowVersion column, incremented by the modified trigger
   cleaned up how the tablename is written to the tablename column 
   added delete trigger, which just writes the table, pk, and operation ('d') to the audit table
   changed [Column] to ColumnName
-----------------------------------
version 1.02 - Jan 16, 2007
   fixed bug: Duplicate Columns. databases with user-defined types was causing the user-defined types to show up as system types. 
   added code gen to create [table]_Deleted view that returns all deleted rows for the table

-----------------------------------
version 1.03 - Jan 16, 2007
   converted from cursor to Multiple Assignment Variable for building of for-each-column code
   added Created, Modified, and deleted columns to _Deleted view 

-----------------------------------
version 1.04 - Jan 18, 2007
  minor clean-up on _Deleted view. Removed extra Primary Key Column. 

-----------------------------------
version 1.05 - Jan 18, 2007
  changed from writing just the delete bit to writing the whole row. 
  modified _Deleted view to return RowVersion

-----------------------------------
version 1.06 - Jan 30, 2007
  added host_name to audit trail
  improved modified trigger run-away recursive trigger detection
  added basic error-trapping

-----------------------------------
version 1.07 - Feb 6, 2007
  idea from Gary Lail - don't log inserts, only updates
  added pRollbackAudit procedure
  changed all stored procedure names to pName
  CREATE PROC usp AS SELECT OBJECT_NAME( @@PROCID )

-----------------------------------
version 1.08 - June 25, 2008
  case sensitive cleanup
  defaults named properly
  defaults and columns dropped in AutoAuditDrop proc

-----------------------------------
version 1.09 - Oct 15, 2008
  fixed @tablename bug in AutoAuditDrop
  changed audit time from GetDate() to  inserted.Created and  inserted.Modified to keep these times in synch
  changed from 'data type in()' to 'data type not in (xml, varbinary, image, text)'  
  added support for hierarchyID tracking (from Cast to Convert)
  added check: Table must have PK
  added check: PK must not be HierarchyID
  added RowVersion to dbo.Audit, and insert/update/delete procs
  added RowHistory Table Valued Function
  added SchemaAudit table and database trigger
  SchemaAuditDDLTrigger also fires pAutoAudit for Alter_Table events for tables with AutoAudit

-----------------------------------
version 1.09a - Oct 18, 2008
  fixed hard-coded path in _RowHistory dynamic SQL builder code
  changed _RowHistory values not updated from 0 to null
  
-----------------------------------
version 1.09b - Oct 23, 2008
  changed SchemaSchema and .Object to allow nulls for events that do not have schema.object
  
-----------------------------------
version 1.10 - Jan 24, 2010

  issue: NULL Updates that don't actually update anything 
    were still updating the Modified column
    and incrementing the RowVersion
  fix: 
    eliminated  the Modified trigger
    moved updating the Modified Column and incrementing the version number to the Update Trigger
    
  moved update of Created col to insert trigger
  added Modified and RowVersion col to Updated
  
  improved error reporting slightly
  
  added capture of user's SQL Statement/Batch
  
  added SET ARITHABORT ON : bug and fix reported by pjl on CodePlex on Jun 15 2009 at 9:35 AM
 
  added CreatedBy and ModifiedBy columns. If names passed to tables, then this value captured for Audit trail.

-----------------------------------
version 1.10e - Mar 20, 2010
  
  cleaned up documentation
  cleaned up sysname data type for parameters
  added .dbo as default to schema parameter
  added drop of audit tables and ddl trigger to pAutoAuditDropAll

-----------------------------------
version 2.00 - April 5, 2010

  Added StrictUserContext Option
     @StrictUserContext = 1
       if 1 then blocks DML inserting or updating Created, CreatedBy, Modified, ModifiedBy
       if 0 then permits DML setting of Created, CreatedBy, Modified, ModifiedBy
       
-----------------------------------
version 2.00c - April 26, 2010
   increased Application column to 128 to allow for SSIS package names 
 
-----------------------------------
version 2.00d - May, 2010 
   bug fixes for StrictSUer Context

-----------------------------------
version 2.00e July, August 2010

  more bug fixes for StrictSUer Context

-- Get Modified working tweak CreatedBy no updated logic
 
  added @LogSQL option
  added @BaseTableDDL option
  
-----------------------------------
version 2.00f July, August 2010
  added @LogInsert option 

-----------------------------------
version 2.00g August, 2010
  removed CreatedBy, ModifiedBy from RowHistory function
  
  added sql_variant to the list of not audited data types
  it was giving the RowHistory function a conumption
  
  Added brackets around primary key column name in RowHistory function (reported by Anthony - SQLDownUnder) 
  
-----------------------------------
version 2.00g August, 2010
  fixed drop of SchemaTable in pAutoAuditDropAll (reported by Calvin Jones)
  changed StrictUserContext ModifiedBy column constraint to NOT NULL (reported by Calvin Jones)
  removed variable initialization for SQL Server 2005 compatability (reported by Calvin Jones) 
  removed SchemaAudit from pAutoAuditAll and pAutoAuditDropAll (Reproted by jeffcj)


-----------------------------------
version 2.00i Sept, 2010 
  changed SYSNAME to sysname for case sensitive collation
  added code to block recursive runs of the trigger
  
-----------------------------------
version 2.00j  Oct 7, 2010 
  RowVersion function incorrectlty reports initial null values and the first non-null value for initial row 


-----------------------------------
version 3.00 January, 2012 (coded by John Sigouin)
  1.Added code to implement row version in the Audit table when the 
    base table DDL audit columns do not exist
  2.Updated the _Deleted view so that it shows all the deletes for each PK 
    (in case a row is inserted,deleted,inserted,deleted...)
  3.Added a column to the _Deleted view to flag latest delete for each PK
  4.Modified the Update trigger to handle updates of the PK when a single 
    row is updated (even if it's bad to update a PK, sometimes it can happen)
  5.Updated the _RowHistory function to make it return the full history even 
    after a row is deleted and re-inserted
  DONE! RowHistory() requires an existing row for the current row. Therefore,
    it fails when viewing the RowHistory() of a deleted row. (reported by sathish4000)

  6.Added code to drop CreatedBy_df and ModifiedBy_df defaults in pAutoAuditDrop
    Added code to drop CreatedBy and ModifiedBy audit columns in pAutoAuditDrop
  7.Changed SchemaObject column datatype from varchar(50) to sysname
  8.Changed the PrimaryKey column datatype from varchar(25) to varchar(36) 
    to accomodate guid's
  9.Added the SchemaAuditID column to the SchemaAudit table and set it as the 
    primary key. There was no Primary Key on that table previously.
 10.Added parameter to this script to allow user to specify a schema for the 
    AutoAudit tables, SPs, views etc (default is [Audit])
		- the _Deleted views and the _RowHistory objects can also be created 
          in the specified schema (which could be the same as the AutoAudit schema),
          the same schema as the base table with the <TableSchema> keyword or any 
          other existing schema as specified.
  DONE! Schema is a parameter to this script - Change all code to Audit schema (suggested by Calvin Jones)

 11.Created a new Audit table called [AuditSettings] to store AutoAudit 
    configuration and default settings. 
 12.Normalized the Audit table by creating a AuditHeader table and a AuditDetail table. 
 13.Create the [vAudit] view joining the AuditHeader and AuditDetail tables so that 
    the [vAudit] view looks just like the former [Audit] table.
 14.Used a unpivot query to insert the AuditDetail records rather than the current 
    individual insert for each column.
 15.The normalization and unpivot modification produced a performance improvement 
    of over 70% on inserts.
 16.Re-designed the _deleted view for optimization with the new table structure.
 17.Created a new _RowHistory view to return the row history through a view rather 
    than a Table-Valued UDF.
 18.Redesigned the _RowHistory Table-Valued UDF to use the new _RowHistory view for 
    backward compatibility.
 19.Updated the pAutoAuditDrop SP to remove the new objects.
 20.Created one new index for performance on AuditHeader.PrimaryKey 
 21.The pAutoAudit SP parameter behaviour has been modified to accomodate the 
    AuditHeader and AuditDetail table structure. The level of detail logged during 
    insert, update and delete operations can be controlled.
      FOR INSERTS: (this was in 2.00h)
		- When @LogInsert = 2, the _Audit_Insert trigger writes an entry to the 
          AuditHeader table and also inserts to the AuditDetail table. 
          This logs the creation of the record and each column value inserted.
		- When @LogInsert = 1, the _Audit_Insert trigger writes an entry to the 
          AuditHeader table but does not insert anything to the AuditDetail table. 
          This logs the creation of the record only.
		- When @LogInsert = 0, the insert event is not logged at all in the Audit tables.
		  The insert trigger is not created.

     FOR UPDATES:
        ******************************************************************************
        WARNING: BE AWARE THAT IF YOU SET @LogUpdate TO ANYTHING OTHER THAN 2 YOU WILL 
				 NOT BE ABLE TO RE-CREATE THE DATA IN YOUR TABLE FOR RECOVERY OF 
				 ACCIDENTAL MODIFICATIONS.
        ******************************************************************************
		- When @LogUpdate = 2, the _Audit_Update trigger writes an entry to the 
          AuditHeader table and also inserts to the AuditDetail table. 
          This logs the update of the record and each of the updated column values.
		- When @LogUpdate = 1, the _Audit_Update trigger writes an entry to the 
          AuditHeader table but does not insert anything to the AuditDetail table. 
          This logs the update of the record only.
		- When @LogUpdate = 0, the update event is not logged at all in the Audit tables.
		  The update trigger is not created unless @BaseTableDDL = 1.
		DONE! LogUpdate Option to turn off Update Trigger ??

     FOR DELETES:
        ******************************************************************************
        WARNING: BE AWARE THAT IF YOU SET @LogDelete TO ANYTHING OTHER THAN 2 YOU WILL 
				 NOT BE ABLE TO RE-CREATE THE DATA IN YOUR TABLE FOR RECOVERY OF 
				 ACCIDENTAL MODIFICATIONS.
        ******************************************************************************
		- When @LogDelete = 2,the _Audit_Delete trigger writes an entry to the 
          AuditHeader table and also inserts to the AuditDetail table. 
          This logs the deletion of the record and each column value before the delete.
		- When @LogDelete = 1,the _Audit_Delete trigger writes an entry to the 
          AuditHeader table but does not insert anything to the AuditDetail table. 
          This logs the deletion of the record only.
		- When @LogDelete = 0,the delete event is not logged at all in the Audit tables.
		  The delete trigger is not created.

 22.Added parameters to pAutoAuditAll SP to match the ones in pAutoAudit except 
    the table schema and name.
 23.Changed the call to pAutoAudit from pAutoAuditAll to forward the specified 
    parameters instead of always using defaults.
 24.Added parameters to pAutoAuditDropAll SP to pick exactly which AutoAudit 
    components are being dropped.
			@DropAuditTables bit=1,	--0 = don't drop audit tables, 1 = drop audit tables
									-- if @DropAuditTables=1 then @DropAuditViews,@DropBaseTableTriggers,
									-- @DropAuditSPs and @DropAuditDDLTriggers defaults to 1
			@DropAuditViews bit=1,	--0 = don't drop audit views, 1 = drop audit views
			@DropAuditSPs bit = 1, --0 = don't drop audit SP's, 1 = drop audit SP's
			@DropAuditDDLTriggers bit = 1, --0 = don't drop audit database DDL trigger, 1 = drop audit database DDL trigger
			@DropBaseTableDDLColumns bit = 1, --0 = don't drop Base Table DDL Columns, 1 = drop  Base Table DDL Columns
			@DropBaseTableTriggers bit = 1, --0 = don't drop audit triggers on tables, 1 = drop audit triggers on tables
			@DropBaseTableViews bit=1	--0 = don't drop BaseTable views, 1 = drop BaseTable views

 25.Changed the call to pAutoAuditDrop from pAutoAuditDropAll to forward the specified 
    parameters instead of always using defaults.
 26.Added print statements to sp's to inform the administrator exactly what is happening.
 27.Added Quotename(...) delimiters all over. AutoAudit will work even if you have a table named 
    [ $chem@].[This is my test crazy table name! ] and a column named [$ Amount].  :-)
    DONE! QuoteName() (suggested by Rob Farley)

 28.The base table schema does not have to be the same as the schema used for the AutoAudit tables.
 29.Corrected a bug with the Update trigger where if a statement was executed with
    an exec or execute_sql prefix (eg. exec (N'Update mytable set Column1 = 'newvalue' 
    where Column1 = 'oldvalue'') compared to Update mytable set Column1 = 'newvalue' 
    where Column1 = 'oldvalue'. With the exec or execute_sql syntax, the RowVersion 
    column was not being incremented in the base table.
 30.Added a configuration switch to the AuditSettings table to enable/disable the 
    Database DDL Trigger.
    DONE! Option Switch for DDLSchemaLog 

 31.Created a new table called AuditBaseTables.  
		-Whenever a table is setup for AutoAudit, a record with the specific AutoAudit 
         for this base table is created in the AutoAuditBaseTables table.  Subsequently, 
         AutoAudit functionality can be enabled/disabled on a table by table basis by 
         toggling the EnabledFlag column value. (ie. may want to disable before inserting 
         updating or deleting millions or records).
		-If the auditing settings (StrictUserContext,LogSQL,BaseTableDDL,LogInsert) needs 
         to be changed on a base table(s), that can be done in this table. After the flags
         have been changed, execute the pAutoAuditRebuild SP to implement the new settings.
    DONE! in the AuditBaseTables table instead of extended properties
	set options in extended properties (suggested by Calvin Jones)
  
                EXEC sp_addextendedproperty 
                    @name = N'StrictUserContext', @value = 1,
                    @level0type = N'Schema', @level0name = Juror,
                    @level1type = N'Table',  @level1name = tblJuror,
                    @level2type = N'TRIGGER', @level2name = trg_Juror_Audit_Delete;

              SELECT * FROM ::fn_listextendedproperty('StrictUserContext', 'SCHEMA','Juror', 'TABLE','tblJuror', 'TRIGGER','trg_Juror_Audit_Delete')
              WHERE value=1

 32.Created a new SP called pAutoAuditRebuild to re-create the AutoAudit trigger on a table 
    if the table's AutoAudit settings have been changed in the AuditBaseTables table or if 
    columns have been added/modified in a base table.
 32.Created a new SP called pAutoAuditRebuildAll to execute the pAutoAuditRebuild sp for 
    each of the tables that exist in the AuditBaseTables table.
 23.Changed [SchemaAuditDDLTrigger] trigger to call pAutoAuditRebuild after a ALTER_TABLE event.
 34.Forced exclusion of AuditHeader, AuditDetail, SchemaAudit tables in pAutoAuditAll SP.
 35.Created a new table called AuditAllExclusions.  All tables listed in this table will be 
    excluded from the pAutoAuditAll and pAutoAuditRebuildAll SP's.  You can use this to 
    customize your own exclusions.

  Exclude MS tables and Audit schema table from AutoAuditAll (suggested by Calvin Jones)
  DONE! exclusion of AuditHeader, AuditDetail, SchemaAudit tables and added a table 
        to specifify any other exclusions.

 36.Created tables to store AutoAudit archive data. The tables are called AuditHeaderArchive
    and AuditDetailArchive. Added indexes to the Archive tables.
  DONE! Archiving of Audit table
    Move to Archive table proc set up as Job
    Indexing of Archive table
    View to Union Audit and AuditArchive tables

 37.Created the vAuditArchive view. Identical to the vAudit view but for the Archive tables.
 38.Created the vAuditAll view which unions the vAudit (active) and vAuditArchive views.
 39.Created the vAuditHeaderAll view which unions the AuditHeader and AuditHeaderArchive tables.
 40.Created the vAuditDetailAll view which unions the AuditDetail and AuditDetailArchive tables.
 41.Created a Stored Procedure <AuditSchema>.pAutoAuditArchive to move data from the active
    Audit tables to the archive tables and to delete the archive data past the retention
    period. The retention periods are user defined in the AuditSettings table.  Even if 
    an Audit record should be archived based on its dates and the @KeepLastEntry parameter
    is set to 1 (default), it will remain in the active tables
    if it is the last audit entry for a particuler TableName-PrimaryKey combination to retain
    row version sequence for future Audit entries. The call to this SP should be setup as a 
    SQL Server Agent scheduled job to run daily or weekly.
 42.Added settings "RowHistory View Scope" and "Deleted View Scope" in the AuditSettins table  
    that determines the scope of the _RowHistory and _Deleted views.  Valid entries are: 
    "Active", "Archive", "All". This setting is used when the views are created, it is not 
    dynamically verified everytime the view is used for performance reasons.
    "All" includes "Active" and "Archive". Default is "Active"
 43.Added a section to this script to automagically transfer the existing legacy single Audit 
    table data to the new tables in the case where this is an upgrade to a version 2.00h installation.
 44.Added Audit Settings to flag if the _RowHistory view, _RowHistory function and _Deleted
    view are created when AutoAudit triggers are added to a table.
 45.Added a seperate variable to identify the schema to use for the AutoAudit base table views.
    I had set it up originally to use the same schema as the Audit tables but I think some DBA's
    might want to match the schema of the data table or use a different schema altogether.  The
    options for this parameter are: The first option is a specific schema for example 
    "Audit" or "dbo" or any other schema.  The second option is "<TableSchema>" which means  
    match the view schema to the table schema.
 46.Use context_info to prevent the _update trigger from firing when the _insert trigger writes
    the Created, Modified and RowVersion data to the base table. Same process for preventing the 
    database DDL trigger from firing when the Created, Modified and RowVersion columns are added
    to the base table.
 47.Used Convert(varchar,<input>,113) instead of cast(<input> as varchar) when inserting data 
    into the AuditDetail table to maintain the full precision of datetime columns.  The cast 
    function method in version 2.00h was saving the OldValue and NewValue date entries in this
    format "Dec 15 2011  7:56PM" thereby loosing the seconds and milliseconds.
 48.An optional index can be created to improve the performance of the _delete and _RowHistory 
    views by a factor of 10 on the AuditDetail.AuditHeaderID column. The downside is the  
    AutoAudit loging uses about 20% more I/O and is 10% slower. The script parameter 
    @OptimizeForAudit = 0 creates the index to speed up views (and slow down AutoAudit) and 
    @OptimizeForAudit = 1 keeps AutoAudit faster but the views and archiving of old Audit 
    data are slower.  Set the parameter to your preference before running this script or
    create/drop the index manually as you wish.
 49.Restructured the AutoAudit Update trigger to correctly record the RowVersion when a query 
    updates multiple records but not all of the records are actually changed. For example:
    Update Items set Status = 'Active'; If some of the records already had a Status='Active'
    their RowVersion was being incremented in base tables where the BaseTableDDL columns were
    added even if there was no actual change and no Audit data recorded.
    Now, only the records that are actually changed have their RowVersion, Modified
    and ModifiedBy updated.
 50.Added the "Source" column in the _RowHistory and _Deleted views to indicate if the rows
    comes from the "active" or "archive" Audit tables.
 

-----------------------------------
version 3.01 January, 2012 (coded by John Sigouin)
   1. Added the SysUser column to the _RowHistory view and _RowHistory() function.
   DONE! Add SysUser to RowHistory (Requested by Patrick Jackman)

   2. Added the DeletedBy (SysUser) column to the _Deleted view.
   DONE! Add DeletedBy column to the v_Deleted view

   3. Retested with Case Sensitive Collation using SQL_Latin1_General_CP1_CS_AS database 
      collation. Made corrections to make it all work.
   DONE! Must retest with Case Sensitive Collation

   4. Added debug option to Audit triggers.  When the "Audit Trigger Debug Flag" setting  
      is set to 1 (on) in the AuditSettings tables, The trigger name and nest level will 
      be returned. 
      The default setting is 0 (off).
   DONE! Debug Option - when true includes print statements to report the execution of the trigger and the nest level

   5. Added calls to sp_addextendedproperty when DDL columns are added to the base table 
      with the @BaseTableDDL = 1 option.
   DONE! Add MS_Description extended property to columns added by AutoAudit (suggested by Calvin Jones)

   6. Added a parameter to flag the creation of extended properties as 1=create, 
      0=do not create.  The setting name is "Add Extended Properties Flag" in the AuditSettings table.
      The default value is 1.

   7. Added the following entries to the AuditAllExclusions tables. 
			- AuditAllExclusions
			- AuditBaseTables
			- AuditSettings
      Setting up AutoAudit on these tables is OK but they are excluded by default. If you 
      want AutoAudit to be setup on these tables, simply remove the names from the 
      AuditAllExclusions table or use the pAutoAudit stored procedure to set them up individually.

   8. Bug fix: Corrected the creation of the _RowHistory table function to refer to @ViewSchema.v_RowHistory
      rather that @AuditSchema.v_RowHistory.

   9. Added a call to pAutoAuditDrop in the Database DDL trigger when a table is dropped to
      automatically drop the AutoAudit views that were related to that table.

  10. Added code to delete AuditBaseTables record from pAutoAuditDrop when a table is dropped.

  11. Added the option for users to rename the Created, CreatedBy, Modified, ModifiedBy, RowVersion
      columns at the beginning of this script. Note: Column names must be standard SQL Server column
      names that do not require to be processed by QUOTENAME.
   DONE! User options to set DDL Column names (Created, CreatedBy, Modified, ModifiedBy, RowVersion) (Suggested by Neal Walters) 

      
-----------------------------------
version 3.02 February, 2012 (coded by John Sigouin)
   1. Created stored procedure pAutoAuditSetTriggerState that enables/disabled the 
      insert, update and/or delete AutoAudit triggers for the specified base table.
      This is different from the EnabledFlag in the AuditBaseTables table because the triggers
      are enabled/disabled at the SQL Server level.
      **********************************************************************************
      WARNING: BE AWARE THAT IF YOU DISABLE AutoAudit TRIGGERS YOU WILL NOT HAVE ANY
               RECORD OF DATA MANIPULATION EVENTS FOR THE UNDERLYING TABLE.  DISABLING
               TRIGGERS SHOULD ONLY BE DONE WHEN YOU ARE LOADING MASSIVE AMOUNTS OF DATA
               INTO YOUR TABLE AND YOU PLAN ON USING YOUR STANDARD BACKUP STRATEGY TO 
               PROTECT YOUR DATA. MAKE SURE YOU RE-ENABLE THE AutoAudit TRIGGERS ONCE 
               YOUR ADMINISTRATIVE OPERATIONS ARE DONE.
      **********************************************************************************
      

-----------------------------------
version 3.20 January, 2013 (coded by John Sigouin)
   1. Add the @WithLogFlag flag to this script
		- This flag determines if the "With Log" function is included in the raiserror statements or not
		- this is added because some DBA's may not have rights to write to the Windows log
		- 0 = exclude "with log", 1 = include "with log"
   2. Add capability for AutoAudit to handle tables with multi-column PK's. AutoAudit is now capable of 
      handling tables which have up to 5 columns used in the definition of the primary key.
		- There is still a maximum width of 36 characters for each PK column
		- The _RowHistory table-valued functions have a number of input parameters to match the number of
		  PK columns in the base table
   3. Add the @ColumnNames optional parameter to pAutoAudit to specify a sub-set of the base tables 
      columns to include in the AuditDetail loging of changes.
        - The columns must be listed in the following format '[column1],[column2],...' where each column
          name is enclosed in square brackets.
        - The primary key column(s) do not need to be listed as they are always included.
        - The default value for this parameter '<All>' indicates that all columns are to be included.
        - The setting for this parameter is written to the AuditBaseTables table as used when AutoAudit
          triggers are rebuilt.


-----------------------------------
version 3.20a January, 2013 (coded by John Sigouin)
    1. Added RowVersion column to list of included columns in the IX_AuditHeader_PrimaryKey index
    2. Added Application and SQLStatement columns to the _RowHistory views and _RowHistory table-valued 
      functions

-----------------------------------
version 3.20b February, 2013 (coded by John Sigouin)
    1. Reworked the _RowHistory table-valued functions to return full row-by-row details of the audit 
       events when the Logging level is set to 2 (full loging) for Insert, Update and Delete events.  
       When Insert Logging is set to 0 (none) or 1 (minimal), then that basic output (which is the 
       same as the _RowHistory views) isreturned.

-----------------------------------
version 3.20d February, 2013 (coded by John Sigouin)
    1. Fixed bug related to the _RowHistory creation script. 
		- missing "and		si.indid = sik.indid" table join criteria
		- handling of max (-1) column size
		- fixed problem when PK was not at the beginning of table columns

version 3.20d April, 2013 (coded by John Sigouin)
	1. Added SET ANSI_PADDING ON statement to [SchemaAuditDDLTrigger] trigger to resolve bug

-----------------------------------
version 3.20e October, 2013 (coded by John Sigouin)
    1. Set the Trigger order to run first for the AutoAudit insert triggers. This change is implemented 
    to process AutoAudit insert triggers correctly where there is another insert trigger in the table.  
    If that other insert trigger ends up updating or deleting the inserted trigger, all the steps will 
    be logged in the AuditDetail table.


-----------------------------------
version 3.20f November, 2013 (coded by John Sigouin)
	1. Added missing [ ] in _RowHistory UDF creation script. Suggested by patrikwiik
	2. Added 'RolePermissions','sysdiagrams' and t.name not like 'aspnet_%' in list of excluded tables 
	in the pAutoAuditAll sp. Suggested by patrikwiik
	
	
-----------------------------------
version 3.20g November, 2013 (coded by John Sigouin)
	1. Corrected bug with the _RowHistory UDF where the function would fail when a non string nullable 
	column or string column narrower than 8 characters. (Submitted by Rolv)
	
	
-----------------------------------
version 3.20h November, 2013 (coded by John Sigouin)
	1. Modified the logic for logging ModifiedBy and ModifiedDate values when @StrictUserContext = 0 
	during an update operation with the following logic
		- if values are updated to those columns with the user query, then those values are kept and 
		used in the AuditHeader table (columns AuditDate, SysUser)
		- if NULL values are updated to those columns with the user query, then AutoAudit uses the 
		server time and the logged in user name in the base table and in the AuditHeader table
		- if the values for the ModifiedBy and ModifiedDate are left unchanged with the update 
		statement, then the previous values will remain in the base table and be used again in the 
		AuditHeader table
	2. Modified the logic for saving AuditDate and SysUser values in the AuditHeader table when 
	@StrictUserContext = 0 during a delete operation. 
		- In the previous versions, the delete trigger was using the 
		  last entries for CreatedDate and CreatedBy in the base table as the source for the AuditDate 
		  and SysUser entries in AuditHeader. This has been corrected to use the ModifiedDate and 
		  ModifiedBy base table columns instead. Therefore, if you want to log the current client time  
		  and login during a delete, you now have to update (touch operation) the ModifiedBy and  
		  ModifiedDate base table columns just before doing your delete.
	3. Changed the sort order for the _RowHistory UDF from AuditDate,[RowVersion] to [RowVersion],AuditDate
	4. Removed the @AuditSchema variable declaration and initialization from the SchemaAuditDDLTrigger 
	   trigger because it was not used.
	5. Added an option in pAutoAuditAll to exclude all tables from specific schemas as required. For 
	   example, if you have tables in schema [MySchema] and you want them to be excluded from 
	   AutoAudit trigger creation when you run pAutoAuditAll, you can add this exclusion row in the 
	   AuditAllExclusions SchemaName = MySchema, TableName = <All>.
	6. Added RowVersion to the list of column datatypes that are not supported by AutoAudit. 
	7. Added filter on primary key column datatypes that are not allowed: 'binary', 'varbinary', 
	   'timestamp', 'rowversion'
	8. Added SQL_Variant datatype columns back in as allowed datatypes for AutoAudit columns
	
	
-----------------------------------
version 3.30 December, 2013 (coded by John Sigouin)
	1. Added a new powerful feature to AutoAudit, the creation of the _TableRecovery table-valued UDF. 
	   This UDF takes a date/time value as parameter and returns a recordset of the contents of the 
	   table as it was at that point in time. This data can be used to recover accidently modified data, 
	   populate reports etc.
	2. Added the Comment column to the AuditAllExclusions table to optionally document the reason
	   for the exclusion. (suggested by rosacek)
	3. Added a variable to configure the date style AutoAudit uses for entries in the AuditHeader and 
	   AuditDetail tables
	4. Added User option to set the prefix on AutoAudit views and UDF (suggested by rosasek)
	5. Added User option to set the suffix on AutoAudit views and UDF (why not go all the way! :-) )
	6. Changed the defaults for pAutoAuditDropAll to 0 instead of 1 and added a confirmation input 
	   parameter as failsafe measures to prevent accidental removal of AutoAudit.
	7. Added the LoginName column to the SchemaAudit table.
	8. Added QUOTENAME delimiters around TableName entry in AuditHeader table entries. A script updates 
	   existing entries in AuditHeader and AuditHeaderArchive.
	9. Added the @DateStyle parameter that allows the user to select date style 113 or 121 for date
	   storage in the AuditHeader and AuditDetail tables.
	   

-----------------------------------
version 3.30a December, 2013 (coded by John Sigouin)
	1. Corrected a problem that affected the _RowHistory view, the _RowHistory UDF and the _TableRecovery 
	UDF caused by the existence of Unique constraints or non clustered primary key columns that are not in 
	the first columns of the table or tables with a multiple-column PK that are anywhere or in any column 
	order in the table.
	2. Replace the usage of the SQL 2000 sys.sys... objects with sys.... SQL 2005-12 equivalents
	
-----------------------------------
Possible Next ideas: 
  

*/

--**************** Setup Script Section #1 ****************
-- Create AutoAudit schema, tables, indexes
-- Load AuditSettings table
--*********************************************************

SET ANSI_NULL_DFLT_ON ON
SET ANSI_NULLS ON
SET ANSI_PADDING ON
SET QUOTED_IDENTIFIER ON

If (select count(*) from sys.objects where [name] = 'AuditSettings' and schema_name(schema_id) <> @AuditSchema) > 0
	Begin
		Print 'An existing installation of AutoAudit with a different schema has been found in the database.'
		Print 'You must remove the existing AutoAudit before installing it to a different schema.'
		Print '***Installation cancelled.'
		set noexec on
		Return
	End 

Print getdate()
Print 'Installing AutoAudit in database: ' + db_name(db_id())

DECLARE @SchemaSQL NVARCHAR(max)

--Save the AuditSchema to a temp table
begin try
	drop table #Settings
end try
begin catch
end catch

Create table #Settings ([SettingName] VARCHAR(50),[SettingValue] VARCHAR(max));
Insert into #Settings ([SettingName],[SettingValue]) values ('AuditSchema',@AuditSchema);
Insert into #Settings ([SettingName],[SettingValue]) values ('Version',@Version);
Insert into #Settings ([SettingName],[SettingValue]) values ('DetailedMigrationCheck',@DetailedMigrationCheck);
Insert into #Settings ([SettingName],[SettingValue]) values ('RebuildTriggersAfterInstall',@RebuildTriggersAfterInstall);

--start by dropping the DDL trigger
If Exists(select * from sys.triggers where name = 'SchemaAuditDDLTrigger')
   DROP TRIGGER SchemaAuditDDLTrigger ON Database

--create the Schema if required
IF @AuditSchema <> 'dbo' and @AuditSchema <> '' and @AuditSchema is not null
	BEGIN
		IF not exists (SELECT [name] FROM sys.schemas where [name] = @AuditSchema)
			Begin
				Print 'Creating AutoAudit Schema' 
				SET @SchemaSQL = 'CREATE SCHEMA ' + quotename(@AuditSchema) + ' AUTHORIZATION [dbo];'
				EXEC (@SchemaSQL)
			END
	END
ELSE 
	SET @AuditSchema = 'dbo'

Print 'AutoAudit schema has been set to: ' + quotename(@AuditSchema)

Print 'Creating AutoAudit tables'

--create the [AuditSettings] table
IF Object_id(quotename(@AuditSchema) + '.[AuditSettings]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditSettings] (
			AuditSettingID INT NOT NULL IDENTITY CONSTRAINT PK_AuditSettings PRIMARY KEY CLUSTERED,
			[SettingName] VARCHAR(100) NOT NULL CONSTRAINT U_AuditSettings_SettingName UNIQUE,
			[SettingValue] VARCHAR(100) NULL,
			[AdditionalInfo]  VARCHAR(max) NULL
			);'
		EXEC (@SchemaSQL)
	END

SELECT	@SchemaSQL = 'DELETE	' + quotename(@AuditSchema) + '.[AuditSettings]
WHERE	[SettingName] in (''AuditSchema'', ''Version'');'
		EXEC (@SchemaSQL)

--insert initial values into [AuditSettings]
--AuditSchema
SELECT	@SchemaSQL = 'DELETE FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''AuditSchema''' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''AuditSchema'',''' + @AuditSchema + ''',''System setting added by AutoAudit installation SQL script.  Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--Schema for _RowHistory, _TableRecovery and _Deleted objects
SELECT	@SchemaSQL = 'DELETE FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Schema for _RowHistory and _Deleted objects''' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Schema for _RowHistory and _Deleted objects'',''' + @ViewSchema + ''',''User configurable - Schema AutoAudit uses for _RowHistory, _TableRecovery and _Deleted objects. Valid entries can be an existing schema or <TableSchema>. The default is <TableSchema>.'');'
		EXEC (@SchemaSQL)
--Version
SELECT	@SchemaSQL = 'DELETE FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Version''' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Version'',''' + @Version + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--DateStyle
SELECT	@SchemaSQL = 'DELETE FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''DateStyle''' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''DateStyle'',''' + @DateStyle + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table. You can re-run the AutoAudit installation script to change this setting.'');'
		EXEC (@SchemaSQL)

--CreatedColumnName
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''CreatedColumnName'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''CreatedColumnName'',''' + @CreatedColumnName + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--CreatedByColumnName
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''CreatedByColumnName'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''CreatedByColumnName'',''' + @CreatedByColumnName + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--ModifiedColumnName
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''ModifiedColumnName'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''ModifiedColumnName'',''' + @ModifiedColumnName + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--ModifiedByColumnName
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''ModifiedByColumnName'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''ModifiedByColumnName'',''' + @ModifiedByColumnName + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--RowVersionColumnName
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''RowVersionColumnName'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''RowVersionColumnName'',''' + @RowVersionColumnName + ''',''System setting added by AutoAudit installation SQL script. Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
		
--ViewPrefix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''ViewPrefix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''ViewPrefix'',''' + @ViewPrefix + ''',''User configurable (default = "v") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the prefix to use for the _RowHistory and _Deleted views.'');'
		EXEC (@SchemaSQL)
--UDFPrefix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''UDFPrefix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''UDFPrefix'',''' + @UDFPrefix + ''',''User configurable (default = "") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the prefix to use for the _RowHistory and _TableRecovery views.'');'
		EXEC (@SchemaSQL)
--RowHistoryViewSuffix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''RowHistoryViewSuffix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''RowHistoryViewSuffix'',''' + @RowHistoryViewSuffix + ''',''User configurable (default = "_RowHistory") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to use for the _RowHistory views.'');'
		EXEC (@SchemaSQL)
--DeletedViewSuffix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''DeletedViewSuffix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''DeletedViewSuffix'',''' + @DeletedViewSuffix + ''',''User configurable (default = "_Deleted") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to use for the _Deleted views.'');'
		EXEC (@SchemaSQL)
--RowHistoryFunctionSuffix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''RowHistoryFunctionSuffix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''RowHistoryFunctionSuffix'',''' + @RowHistoryFunctionSuffix + ''',''User configurable (default = "_RowHistory") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to use for the _RowHistory functions.'');'
		EXEC (@SchemaSQL)
--TableRecoveryFunctionSuffix
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''TableRecoveryFunctionSuffix'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''TableRecoveryFunctionSuffix'',''' + @TableRecoveryFunctionSuffix + ''',''User configurable (default = "_TableRecovery") - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Sets the suffix to use for the _TableRecovery functions.'');'
		EXEC (@SchemaSQL)

--SchemaAuditDDLTrigger Enabled Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''SchemaAuditDDLTrigger Enabled Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''SchemaAuditDDLTrigger Enabled Flag'',''1'',''User configurable - Immediate change. No action required. 0 = DDL trigger disabled, 1 = DDL trigger enabled.'');'
		EXEC (@SchemaSQL)
--Archive Audit data older than (days)
SELECT	@SchemaSQL = 'IF NOT EXISTS( SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Archive Audit data older than (days)'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Archive Audit data older than (days)'',''30'',''User configurable - Immediate change. No action required. Audit data older than this number of days will be moved to the archive tables when the pAutoAuditArchive stored procedure is executed.'');'
		EXEC (@SchemaSQL)
--Delete Audit data older than (days)
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Delete Audit data older than (days)'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Delete Audit data older than (days)'',''365'',''User configurable - Immediate change. No action required. Audit data older than this number of days will be deleted permanently when the pAutoAuditArchive stored procedure is executed.'');'
		EXEC (@SchemaSQL)
--RowHistory View Scope
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''RowHistory View Scope'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''RowHistory View Scope'',''Active'',''User configurable - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Determines source of data when _RowHistory views are created. Valid entries are: "Active", "Archive", "All".'');'
		EXEC (@SchemaSQL)
--Deleted View Scope
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Deleted View Scope'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Deleted View Scope'',''Active'',''User configurable - Must execute pAutoAuditRebuild(All) or pAutoAudit(All) to apply change. Determines source of data when _Deleted views are created. Valid entries are: "Active", "Archive", "All".'');'
		EXEC (@SchemaSQL)
--Default _RowHistory view Creation Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Default _RowHistory view Creation Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Default _RowHistory view Creation Flag'',''1'',''User configurable - 0 = _RowHistory view is not created, 1 = _RowHistory view is created.'');'
		EXEC (@SchemaSQL)
--Default _RowHistory function Creation Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Default _RowHistory function Creation Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Default _RowHistory function Creation Flag'',''1'',''User configurable - 0 = _RowHistory function is not created, 1 = _RowHistory function is created.'');'
		EXEC (@SchemaSQL)
--Default _TableRecovery function Creation Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Default _TableRecovery function Creation Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Default _TableRecovery function Creation Flag'',''1'',''User configurable - 0 = _TableRecovery function is not created, 1 = _TableRecovery function is created.'');'
		EXEC (@SchemaSQL)
--Default _Deleted view Creation Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Default _Deleted view Creation Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Default _Deleted view Creation Flag'',''1'',''User configurable - 0 = _Deleted view is not created, 1 = _Deleted view is created.'');'
		EXEC (@SchemaSQL)
--Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag'',''1'',''System setting added by AutoAudit installation SQL script.  Do not change manually in the table.'');'
		EXEC (@SchemaSQL)
--Audit Trigger Debug Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Audit Trigger Debug Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Audit Trigger Debug Flag'',''0'',''User configurable - Immediate change. No action required. - 0 = Do not return debug information, 1 = Return trigger name and nest level.'');'
		EXEC (@SchemaSQL)
--Add Extended Properties Flag
SELECT	@SchemaSQL = 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Add Extended Properties Flag'' )' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Add Extended Properties Flag'',''1'',''User configurable - 0 = Do not save extended properties, 1 = Save extended properties for DDL columns.'');'
		EXEC (@SchemaSQL)
--Add Raiserror to Windows Log Flag
SELECT	@SchemaSQL = 'DELETE FROM ' + quotename(@AuditSchema) + '.[AuditSettings] ' 
+ 'WHERE [SettingName] = ''Raiserror to Windows Log Flag''' + Char(13) + Char(10)
+ 'INSERT	' + quotename(@AuditSchema) + '.[AuditSettings] ([SettingName],[SettingValue],[AdditionalInfo])
VALUES	(''Raiserror to Windows Log Flag'','''+ isnull(cast(@WithLogFlag as varchar(1)),'0') + ''',''User configurable - 0 = Do not write error to Windows Log, 1 = Write error to Windows Log.'');'
		EXEC (@SchemaSQL)


--create the [AuditBaseTables] table
IF Object_id(quotename(@AuditSchema) + '.[AuditBaseTables]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditBaseTables] (
			AuditBaseTableID INT NOT NULL IDENTITY CONSTRAINT PK_AuditBaseTables PRIMARY KEY CLUSTERED,
			[SchemaName] sysname NOT NULL,
			[TableName] sysname NOT NULL,
			[StrictUserContext] BIT NOT NULL,
			[LogSQL] BIT NOT NULL,
			[BaseTableDDL] BIT NOT NULL,
			[LogInsert] TINYINT NOT NULL,
			[LogUpdate] TINYINT NOT NULL,
			[LogDelete] TINYINT NOT NULL,
			[EnabledFlag] BIT NOT NULL,
			[ViewSchema]  sysname NOT NULL,
			[ColumnNames] NVARCHAR(MAX) Not Null default (''<All>'')
			);'
		EXEC (@SchemaSQL)
	END

--rename the existing [Audit] table if it exists
IF Object_id('[dbo].[Audit]') IS NOT NULL
	BEGIN
		exec sp_rename 'dbo.Audit', 'LegacyAudit'
		--rename the existing [SchemaAudit] table if it exists
		IF Object_id('[dbo].[SchemaAudit]') IS NOT NULL
			BEGIN
				exec sp_rename 'dbo.SchemaAudit', 'LegacySchemaAudit'
			END
	END

--create the new [SchemaAudit] table
IF Object_id(quotename(@AuditSchema) + '.[SchemaAudit]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[SchemaAudit] (
			SchemaAuditID int not null identity constraint PK_SchemaAudit Primary Key Clustered,
			AuditDate DATETIME NOT NULL,
			LoginName sysname NOT NULL,
			UserName sysname NOT NULL,
			[Event] sysname NOT NULL,
			[Schema] sysname NULL,
			[Object] sysname NULL,
			[TSQL] VARCHAR(max) NOT NULL,
			[XMLEventData] XML NOT NULL
			);'
		EXEC (@SchemaSQL)
	END
ELSE
	BEGIN
		If not exists(Select 1 from syscolumns where OBJECT_NAME(id) = 'SchemaAudit' and [name] = 'LoginName')
			BEGIN
				--SchemaAudit already exists, add LoginName column if required
				Begin try
					SET @SchemaSQL = 'ALTER TABLE ' + quotename(@AuditSchema) + '.[SchemaAudit] 
						Add	[LoginName] sysname NULL;'
					EXEC (@SchemaSQL)
					print 'Added [LoginName] column to SchemaAudit table.'
				End Try
				Begin Catch
					--Comment column already existed
					Raiserror ('Failed adding LoginName column to SchemaAudit table.',0,0)	
				End Catch
			END
	END


--create the [AuditHeader] table
IF Object_id(quotename(@AuditSchema) + '.[AuditHeader]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditHeader] (
			AuditHeaderID BIGINT NOT NULL IDENTITY 
			  CONSTRAINT pkAuditHeader PRIMARY KEY CLUSTERED,
			AuditDate DATETIME NOT NULL,
			HostName sysname NOT NULL,
			SysUser NVARCHAR(128) NOT NULL,
			Application VARCHAR(128) NOT NULL,
			TableName sysname NOT NULL,
			Operation CHAR(1) NOT NULL, -- i,u,d
			SQLStatement VARCHAR(max) NULL, -- new column to capture SQL Statement
			PrimaryKey VARCHAR(36) NOT NULL,
			PrimaryKey2 VARCHAR(36) NULL,
			PrimaryKey3 VARCHAR(36) NULL,
			PrimaryKey4 VARCHAR(36) NULL,
			PrimaryKey5 VARCHAR(36) NULL,
			RowDescription VARCHAR(50) NULL,-- Optional, not used 
			SecondaryRow VARCHAR(50) NULL, -- Optional, not used  
			[RowVersion] INT NULL
			)'
		EXEC (@SchemaSQL)
	END

--create the [AuditDetail] table
IF Object_id(quotename(@AuditSchema) + '.[AuditDetail]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditDetail] (
			AuditDetailID BIGINT NOT NULL IDENTITY 
			  CONSTRAINT pkAuditDetail PRIMARY KEY CLUSTERED,
			AuditHeaderID BIGINT NOT NULL 
			  CONSTRAINT fkAuditHeader FOREIGN KEY REFERENCES ' + quotename(@AuditSchema) + '.[AuditHeader] (AuditHeaderID),
			ColumnName sysname NULL, -- required for i,u, and now D (ver 1.07), should add check constraint
			OldValue VARCHAR(50) NULL, -- edit to suite (Nvarchar() ?, varchar(MAX) ? ) 
			NewValue VARCHAR(50) NULL -- edit to suite (Nvarchar() ?, varchar(MAX) ? )
			)'  -- optimzed for inserts, no non-clustered indexes
		EXEC (@SchemaSQL)
	END

--create the [AuditAllExclusions] table
IF Object_id(quotename(@AuditSchema) + '.[AuditAllExclusions]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditAllExclusions] (
			AuditAllExclusionID INT NOT NULL IDENTITY CONSTRAINT PK_AuditAllExclusions PRIMARY KEY CLUSTERED,
			[SchemaName] sysname NOT NULL,
			[TableName] sysname NOT NULL,
			[Comment] varchar(256) NULL
			);
			Insert ' + quotename(@AuditSchema) + '.[AuditAllExclusions] (SchemaName, TableName, Comment)
			values (''' + @AuditSchema + ''',''AuditAllExclusions'',''Added by AutoAudit Setup'');
			Insert ' + quotename(@AuditSchema) + '.[AuditAllExclusions] (SchemaName, TableName, Comment)
			values (''' + @AuditSchema + ''',''AuditBaseTables'',''Added by AutoAudit Setup'');
			Insert ' + quotename(@AuditSchema) + '.[AuditAllExclusions] (SchemaName, TableName, Comment)
			values (''' + @AuditSchema + ''',''AuditSettings'',''Added by AutoAudit Setup'');'
		EXEC (@SchemaSQL)
	END
ELSE
	BEGIN
		If not exists(Select 1 from syscolumns where OBJECT_NAME(id) = 'AuditAllExclusions' and [name] = 'Comment')
			BEGIN
				--AuditAllExclusions already exists, add Comment column if required
				Begin try
					SET @SchemaSQL = 'ALTER TABLE ' + quotename(@AuditSchema) + '.[AuditAllExclusions] 
						Add	[Comment] varchar(256) NULL;'
					EXEC (@SchemaSQL)
					print 'Added [Comment] column to AuditAllExclusions table.'
					
					SET @SchemaSQL = 'Update ' + quotename(@AuditSchema) + '.[AuditAllExclusions] 
						set Comment = ''Added by AutoAudit Setup'' 
						where TableName in (''AuditAllExclusions'',''AuditBaseTables'',''AuditSettings'');'
					--print @SchemaSQL
					EXEC (@SchemaSQL)
				End Try
				Begin Catch
					--Comment column already existed
					Raiserror ('Failed adding Comment column to AuditAllExclusions table.',0,0)
				End Catch
			END
	END
		


Print 'Creating AutoAudit table indexes'

--create indexes on AuditHeader table
IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditHeader]') AND name = N'IX_AuditHeader_PrimaryKey')
	BEGIN
		Print '   Creating indexes on AuditHeader.PrimaryKey'
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditHeader_PrimaryKey] ON ' + quotename(@AuditSchema) + '.[AuditHeader] (PrimaryKey) 
						  include (PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, [RowVersion])'
		EXEC (@SchemaSQL)
	END

--create indexes on AuditDetail table
IF @OptimizeForAudit = 0
IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditDetail]') AND name = N'IX_AuditDetail_AuditHeaderID')
	BEGIN
		Print '   Creating indexes on AuditDetail.AuditHeaderID'
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditDetail_AuditHeaderID] ON ' + quotename(@AuditSchema) + '.[AuditDetail] (AuditHeaderID)'
		EXEC (@SchemaSQL)
	END

--create indexes on AuditBaseTables table
IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditBaseTables]') AND name = N'IX_AuditBaseTables_SchemaAndTableName')
	BEGIN
		Print '   Creating indexes on AuditBaseTables'
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditBaseTables_SchemaAndTableName] ON ' + quotename(@AuditSchema) + '.[AuditBaseTables] (SchemaName, TableName)'
		EXEC (@SchemaSQL)
	END

--***********************************************
--Create AutoAudit Archive tables
--***********************************************

--create the [AuditHeaderArchive] table
IF Object_id(quotename(@AuditSchema) + '.[AuditHeaderArchive]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditHeaderArchive] (
			AuditHeaderID BIGINT NOT NULL 
			  CONSTRAINT pkAuditHeaderArchive PRIMARY KEY CLUSTERED,
			AuditDate DATETIME NOT NULL,
			HostName sysname NOT NULL,
			SysUser NVARCHAR(128) NOT NULL,
			Application VARCHAR(128) NOT NULL,
			TableName sysname NOT NULL,
			Operation CHAR(1) NOT NULL, -- i,u,d
			SQLStatement VARCHAR(max) NULL, -- new column to capture SQL Statement
			PrimaryKey VARCHAR(36) NOT NULL,
			PrimaryKey2 VARCHAR(36) NULL,
			PrimaryKey3 VARCHAR(36) NULL,
			PrimaryKey4 VARCHAR(36) NULL,
			PrimaryKey5 VARCHAR(36) NULL,
			RowDescription VARCHAR(50) NULL,-- Optional, not used 
			SecondaryRow VARCHAR(50) NULL, -- Optional, not used  
			[RowVersion] INT NULL
			)'
		EXEC (@SchemaSQL)
	END

--create the [AuditDetailArchive] table
IF Object_id(quotename(@AuditSchema) + '.[AuditDetailArchive]') IS NULL
	BEGIN
		SET @SchemaSQL = 'CREATE TABLE ' + quotename(@AuditSchema) + '.[AuditDetailArchive] (
			AuditDetailID BIGINT NOT NULL 
			  CONSTRAINT pkAuditDetailArchive PRIMARY KEY CLUSTERED,
			AuditHeaderID BIGINT NOT NULL 
			  CONSTRAINT fkAuditHeaderArchive FOREIGN KEY REFERENCES ' + quotename(@AuditSchema) + '.[AuditHeaderArchive] (AuditHeaderID),
			ColumnName sysname NULL,
			OldValue VARCHAR(50) NULL, -- edit to suite (Nvarchar() ?, varchar(MAX) ? ) 
			NewValue VARCHAR(50) NULL -- edit to suite (Nvarchar() ?, varchar(MAX) ? )
			)'  -- optimzed for inserts, no non-clustered indexes
		EXEC (@SchemaSQL)
	END

--create indexes on AuditHeaderArchive table
IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditHeaderArchive]') AND name = N'IX_AuditHeaderArchive_PrimaryKeyTableName')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditHeaderArchive_PrimaryKeyTableName] ON ' + quotename(@AuditSchema) + '.[AuditHeaderArchive] (PrimaryKey,TableName)
						  include (PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5)'
		EXEC (@SchemaSQL)
	END

IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditHeaderArchive]') AND name = N'IX_AuditHeaderArchive_AuditDate')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditHeaderArchive_AuditDate] ON ' + quotename(@AuditSchema) + '.[AuditHeaderArchive] (AuditDate)'
		EXEC (@SchemaSQL)
	END

IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditHeaderArchive]') AND name = N'IX_AuditHeaderArchive_HostName')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditHeaderArchive_HostName] ON ' + quotename(@AuditSchema) + '.[AuditHeaderArchive] (HostName)'
		EXEC (@SchemaSQL)
	END

--create indexes on AuditDetailArchive table
IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditDetailArchive]') AND name = N'IX_AuditDetailArchive_AuditHeaderID')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditDetailArchive_AuditHeaderID] ON ' + quotename(@AuditSchema) + '.[AuditDetailArchive] (AuditHeaderID)'
		EXEC (@SchemaSQL)
	END

IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditDetailArchive]') AND name = N'IX_AuditDetailArchive_ColumnName')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditDetailArchive_ColumnName] ON ' + quotename(@AuditSchema) + '.[AuditDetailArchive] (ColumnName)'
		EXEC (@SchemaSQL)
	END

IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditDetailArchive]') AND name = N'IX_AuditDetailArchive_NewValue')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditDetailArchive_NewValue] ON ' + quotename(@AuditSchema) + '.[AuditDetailArchive] (NewValue)'
		EXEC (@SchemaSQL)
	END

IF  NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(quotename(@AuditSchema) + '.[AuditDetailArchive]') AND name = N'IX_AuditDetailArchive_OldValue')
	BEGIN
		SET @SchemaSQL = 'CREATE INDEX [IX_AuditDetailArchive_OldValue] ON ' + quotename(@AuditSchema) + '.[AuditDetailArchive] (OldValue)'
		EXEC (@SchemaSQL)
	END

go -----------------------------------------------

--**************** Setup Script Section #2 *************************************************************************************
-- Creating vAudit view - This view only supports single column PK's to maintain compatibility with legacy versions of AutoAudit
--******************************************************************************************************************************

DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

Print 'Creating View - vAudit (view for legacy Audit table)'
IF Object_id(quotename(@AuditSchema) + '.[vAudit]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP VIEW ' + quotename(@AuditSchema) + '.[vAudit];'
	EXEC (@SchemaSQL)
  END

SET @SchemaSQL = 'CREATE VIEW ' + quotename(@AuditSchema) + '.[vAudit]' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns data from the live AutoAudit tables formatted to match the AutoAudit 2.00h Audit table.' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SELECT	AH.[AuditHeaderID] as AuditID' + Char(13) + Char(10)
       + '			,AH.[AuditDate]' + Char(13) + Char(10)
       + '			,AH.[HostName]' + Char(13) + Char(10)
       + '			,AH.[SysUser]' + Char(13) + Char(10)
       + '			,AH.[Application]' + Char(13) + Char(10)
       + '			,AH.[TableName]' + Char(13) + Char(10)
       + '			,AH.[Operation]' + Char(13) + Char(10)
       + '			,AH.[SQLStatement]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey2]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey3]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey4]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey5]' + Char(13) + Char(10)
       + '			,AH.[RowDescription]' + Char(13) + Char(10)
       + '			,AH.[SecondaryRow]' + Char(13) + Char(10)
       + '			,AD.[ColumnName]' + Char(13) + Char(10)
       + '			,AD.[OldValue]' + Char(13) + Char(10)
       + '			,AD.[NewValue]' + Char(13) + Char(10)
       + '			,AH.[RowVersion]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditHeader] AH' + Char(13) + Char(10)
       + 'LEFT JOIN ' + quotename(@AuditSchema) + '.[AuditDetail] AD' + Char(13) + Char(10)
       + '	ON		AH.[AuditHeaderID] = AD.[AuditHeaderID];' + Char(13) + Char(10)
EXEC (@SchemaSQL)

go -----------------------------------------------

--**************** Setup Script Section #3 ****************
-- Upgrade AutoAudit 2.00h to 3.00 if required
-- Migrate existing data to new table structure
--*********************************************************

Print ''
Print 'Searching for existing AutoAudit components' 
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'
DECLARE @DetailedMigrationCheck bit
SELECT @DetailedMigrationCheck = [SettingValue] from #Settings where [SettingName] = 'DetailedMigrationCheck'

IF Object_id('dbo.[LegacyAudit]') IS NOT NULL
	BEGIN --the old Audit table has been found import the data into the new structure
		Print '***** Existing AutoAudit components have been found.'
		Print '***** Migration to new tables will be done.'

		--get the record count to process
		DECLARE @RecordCount bigint
		SELECT @RecordCount = isnull(rowcnt,0) FROM sysindexes WHERE object_name(id) = 'LegacyAudit' and indid<2

		Print '***** There are ' + cast(@RecordCount as varchar(10)) + ' audit records to migrate.'
		raiserror ('***** This process may take several minutes!',0,0) with nowait

		--Migrate AuditHeader records
		raiserror ('***** Inserting records to the new AuditHeader table.',0,0) with nowait
		SET @SchemaSQL = 'INSERT ' + quotename(@AuditSchema) + '.AuditHeader
						(AuditDate,HostName,SysUser,[Application],TableName,Operation,SQLStatement,PrimaryKey,
						RowDescription,SecondaryRow,[RowVersion]) 
						select distinct 
						AuditDate,HostName,SysUser,Application,TableName,Operation
						,SQLStatement,PrimaryKey,RowDescription,SecondaryRow,[RowVersion]
						from dbo.LegacyAudit
						order by AuditDate,TableName,PrimaryKey,[RowVersion]'
		EXEC (@SchemaSQL)

		raiserror ('***** Inserting records to the new AuditDetail table.',0,0) with nowait
		SET @SchemaSQL = 'INSERT ' + quotename(@AuditSchema) + '.AuditDetail
						(AuditHeaderID,ColumnName,OldValue,NewValue)
						Select		AH.AuditHeaderID,LA.ColumnName,LA.OldValue,LA.NewValue
						from		' + quotename(@AuditSchema) + '.AuditHeader AH
						inner join	dbo.[LegacyAudit] LA
							on		AH.AuditDate = LA.AuditDate
							AND		AH.PrimaryKey = LA.PrimaryKey
							AND		AH.TableName = LA.TableName
							AND		ISNULL(AH.[RowVersion],-1) = ISNULL(LA.[RowVersion],-1)'
		EXEC (@SchemaSQL)

		--verify that all of the Audit records have been imported to AutoAudit
		raiserror ('***** Starting quick audit data migration verification...',0,0) with nowait

		DECLARE @MigratedRecordCount bigint
		Select	@SchemaSQL = 'Select @MigratedRecordCount = count(*) from ' + quotename(@AuditSchema) + '.vAudit' + CHAR(13) + CHAR(10)
		EXEC sp_executesql @SchemaSQL, N'@MigratedRecordCount BigInt OUTPUT', @MigratedRecordCount OUTPUT
		raiserror ('***** Completed quick audit data migration verification...',0,0) with nowait

		If (select isnull(@MigratedRecordCount,0)) = (select isnull(@RecordCount,0))
			raiserror ('Record count test completed successfully.',0,0) with nowait
		else
			raiserror ('Record count test completed with differences. Please review the audit records that were not migrated.',0,0) with nowait
			
		If @DetailedMigrationCheck = 1
			Begin
				raiserror ('***** Starting detailed audit data migration check...',0,0) with nowait
				SET @SchemaSQL = ';with Delta as (Select AuditDate,HostName,SysUser,[Application],
									TableName,Operation,PrimaryKey,
									ColumnName,OldValue,
									NewValue,[RowVersion] from dbo.[LegacyAudit]
									except
									Select AuditDate,HostName,SysUser,[Application],
									TableName,Operation,PrimaryKey,
									ColumnName,OldValue,
									NewValue,[RowVersion] from ' 
									+ quotename(@AuditSchema) + '.vAudit)' + CHAR(13) + CHAR(10) + '
									Select @DeltaQty = count(*) from Delta;'

						Declare @DeltaQty BigInt
						EXEC sp_executeSQL @SchemaSQL, N'@DeltaQty BigInt OUTPUT', @DeltaQty OUTPUT

						raiserror ('***** Completed detailed audit data migration check...',0,0) with nowait

				If @DeltaQty = 0
					raiserror ('Detailed data migration test completed successfully.',0,0) with nowait
				else
					raiserror ('Detailed data migration test completed with error(s). Please review the audit records that were not migrated.',0,0) with nowait
			End

		print ''
		raiserror ('***** Adding existing Audit settings to the AuditBaseTables table.',0,0) with nowait

		Begin try
			Drop table #DropList
		End Try
		Begin Catch
		End Catch

		Create table #DropList
		(SchemaName sysname, TableName sysname)

		SET @SchemaSQL = '
		INSERT		' + quotename(@AuditSchema) + '.[AuditBaseTables]
					([SchemaName],[TableName],[StrictUserContext],[LogSQL],[BaseTableDDL],[LogInsert],[LogUpdate],[LogDelete],[EnabledFlag],[ViewSchema],[ColumnNames])
		OUTPUT		inserted.[SchemaName],inserted.[TableName] into #DropList
		SELECT	distinct 
					s.name, t.name ,
					case when sc.text like ''%StrictUserContext : 1%'' then 1 else 0 end as StrictUserContext,
					case when sc.text like ''%LogSQL            : 1%'' then 1 else 0 end as LogSQL,
					case when sc.text like ''%BaseTableDDL      : 1%'' then 1 else 0 end as BaseTableDDL,
					case when sc.text like ''%LogInsert         : 1%'' then 1 
						 when sc.text like ''%LogInsert         : 2%'' then 2 else 0 end as LogInsert,
					2 as LogUpdate,
					2 as LogDelete,
					1 as EnabledFlag,
					''dbo'' as ViewSchema,
					''<All>''
		from		sys.tables t
		inner join	sys.schemas s
			on		t.schema_id = s.schema_id
		inner join	sys.triggers tr
			on		t.object_id = tr.parent_id
		inner join	syscomments sc
			on		tr.object_id = sc.id
		where		tr.name like ''%[_]Audit[_]Update%''
			and		sc.colid = 1
			and		s.name + t.name NOT IN
					(
					SELECT [SchemaName] + [TableName]
					  FROM ' + quotename(@AuditSchema) + '.[AuditBaseTables]
					);'
		EXEC (@SchemaSQL)

		--Copy the Legacy SchemaAudit data to the new SchemaAudit table
		raiserror ('***** Inserting records to the new SchemaAudit table. .',0,0) with nowait
		SET @SchemaSQL = '
		INSERT		' + quotename(@AuditSchema) + '.[SchemaAudit] 
				([AuditDate],[UserName],[Event],[Schema],[Object],[TSQL],[XMLEventData])
		SELECT	[AuditDate],[UserName],[Event],[Schema],[Object],[TSQL],[XMLEventData]
		FROM	dbo.[LegacySchemaAudit] order by [AuditDate];'
		EXEC (@SchemaSQL)

		--drop the existing audit related views, functions, triggers
		-- for each distinct audit record event
		DECLARE	@dSchemaName sysname,
				@dTableName sysname

		DECLARE cDrops CURSOR FAST_FORWARD READ_ONLY
		  FOR	SELECT [SchemaName],[TableName] from #DropList

		OPEN cDrops

		FETCH cDrops INTO @dSchemaName,@dTableName   -- prime the cursor
		WHILE @@Fetch_Status = 0 
		  BEGIN
				print '     dropping old Audit objects for table: '+ @dSchemaName+', '+@dTableName

				SET @SchemaSQL = 'drop view ' + @dSchemaName + '.v' + @dTableName + '_Deleted'
				begin try 
					EXEC (@SchemaSQL)
				end try
				begin catch
				end catch
				SET @SchemaSQL = 'drop function ' + @dSchemaName + '.' + @dTableName + '_RowHistory'
				begin try 
					EXEC (@SchemaSQL)
				end try
				begin catch
				end catch
				SET @SchemaSQL = 'drop trigger ' + @dSchemaName + '.' + @dTableName + '_Audit_Insert'
				begin try 
					EXEC (@SchemaSQL)
				end try
				begin catch
				end catch
				SET @SchemaSQL = 'drop trigger ' + @dSchemaName + '.' + @dTableName + '_Audit_Update'
				begin try 
					EXEC (@SchemaSQL)
				end try
				begin catch
				end catch
				SET @SchemaSQL = 'drop trigger ' + @dSchemaName + '.' + @dTableName + '_Audit_Delete'
				begin try 
					EXEC (@SchemaSQL)
				end try
				begin catch
				end catch

				--exec pAutoAuditDrop @dSchemaName, @dTableName
				FETCH cDrops INTO @dSchemaName,@dTableName   -- fetch next
		  END

		CLOSE cDrops
		DEALLOCATE cDrops

		exec sp_rename 'dbo.LegacyAudit', 'LegacyAudit_Migrated'
		exec sp_rename 'dbo.LegacySchemaAudit', 'LegacySchemaAudit_Migrated'

		raiserror ('***** Legacy AutoAudit components have been renamed.',0,0) with nowait
		raiserror ('***** You may drop [LegacyAudit_Migrated] and [LegacySchemaAudit_Migrated] as you wish.',0,0) with nowait
		raiserror ('***** Migration of legacy audit data to new AutoAudit tables completed.',0,0) with nowait
		print ''
	END --IF Object_id('dbo.[LegacyAudit]') IS NOT NULL


--**************** Setup Script Section #4 ****************
-- Drop existing AutoAudit Stored Procedures
--*********************************************************

Print 'Dropping previous revision of AutoAudit components' 

--drop the legacy "dbo" owned sp's
IF Object_id('pAutoAudit') IS NOT NULL
  DROP PROC pAutoAudit
IF Object_id('pAutoAuditAll') IS NOT NULL
  DROP PROC pAutoAuditAll
IF Object_id('pAutoAuditRebuild') IS NOT NULL
  DROP PROC pAutoAuditRebuild
IF Object_id('pAutoAuditRebuildAll') IS NOT NULL
  DROP PROC pAutoAuditRebuildAll
IF Object_id('pAutoAuditDrop') IS NOT NULL
  DROP PROC pAutoAuditDrop
IF Object_id('pAutoAuditDropAll') IS NOT NULL
  DROP PROC pAutoAuditDropAll
IF Object_id('pAutoAuditSetTriggerState') IS NOT NULL
  DROP PROC pAutoAuditSetTriggerState
IF Object_id('pAutoAuditSetTriggerStateAll') IS NOT NULL
  DROP PROC pAutoAuditSetTriggerStateAll

--drop the "schema" owned sp's
IF Object_id(quotename(@AuditSchema) + '.[pAutoAudit]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAudit];'
	EXEC (@SchemaSQL)
  END
IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditAll];'
	EXEC (@SchemaSQL)
  END
IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditDrop]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditDrop];'
	EXEC (@SchemaSQL)
  END
IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditDropAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditDropAll];'
	EXEC (@SchemaSQL)
  END
IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditRebuild]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditRebuild];'
	EXEC (@SchemaSQL)
  END
IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditRebuildAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditRebuildAll];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditArchive]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditArchive];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditSetTriggerState]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditSetTriggerState];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[pAutoAuditSetTriggerStateAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP PROC ' + quotename(@AuditSchema) + '.[pAutoAuditSetTriggerStateAll];'
	EXEC (@SchemaSQL)
  END

If Exists(select * from sys.triggers where name = 'SchemaAuditDDLTrigger')
   DROP TRIGGER SchemaAuditDDLTrigger ON Database
   
--drop views
IF Object_id(quotename(@AuditSchema) + '.[vAuditArchive]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP VIEW ' + quotename(@AuditSchema) + '.[vAuditArchive];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[vAuditAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP VIEW ' + quotename(@AuditSchema) + '.[vAuditAll];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[vAuditHeaderAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP VIEW ' + quotename(@AuditSchema) + '.[vAuditHeaderAll];'
	EXEC (@SchemaSQL)
  END

IF Object_id(quotename(@AuditSchema) + '.[vAuditDetailAll]') IS NOT NULL
  BEGIN
	SET @SchemaSQL = 'DROP VIEW ' + quotename(@AuditSchema) + '.[vAuditDetailAll];'
	EXEC (@SchemaSQL)
  END

go -----------------------------------------------

--**************** Setup Script Section #5 ****************
-- Create DDL Database Trigger
--*********************************************************

Print 'Creating DDL Trigger' 
--the creation of the DDL trigger has been setup with the EXEC(@SQLSchema) style
--to be able to code the schema on the SchemaAudit table
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

SET @SchemaSQL = '
--Note: Database triggers must be created in the dbo schema   
CREATE TRIGGER [SchemaAuditDDLTrigger]
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS
AS 
BEGIN

  -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10) 
  +'-- www.SQLServerBible.com 
  -- Paul Nielsen and John Sigouin
  SET NoCount ON
  SET ARITHABORT ON
  SET ANSI_PADDING ON
  
declare @ContextInfo varbinary(128)
select @ContextInfo = context_info from master.dbo.sysprocesses where spid=@@SPID;

--check for recursive execution  of trigger 
IF @ContextInfo = 0x1
	RETURN 

  If 0 = isnull((SELECT [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''SchemaAuditDDLTrigger Enabled Flag''),1)
	RETURN --The database DDL trigger configuration is set to disabled

  DECLARE 
    @EventData XML,
    @Schema sysname,
    @Object sysname,
    @EventType sysname,
    @SQL VARCHAR(max)
    
  SET @EventData = EventData()
  
  SET @Schema = @EventData.value(''data(/EVENT_INSTANCE/SchemaName)[1]'', ''VARCHAR(50)'')
  SET @Object = @EventData.value(''data(/EVENT_INSTANCE/ObjectName)[1]'', ''VARCHAR(50)'')
  SET @EventType = @EventData.value(''data(/EVENT_INSTANCE/EventType)[1]'', ''VARCHAR(50)'')
  
  INSERT ' + quotename(@AuditSchema) + '.SchemaAudit (AuditDate, LoginName, UserName, [Event], [Schema], Object, TSQL, [XMLEventData])
  SELECT 
    GetDate(),
    SUSER_SNAME(),
    @EventData.value(''data(/EVENT_INSTANCE/UserName)[1]'', ''sysname''),
    @EventType, @Schema, @Object,
    @EventData.value(''data(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]'', ''VARCHAR(max)''),
    @EventData
    
  If 1 = isnull((SELECT [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag''),1)
  IF @EventType = ''ALTER_TABLE''
    BEGIN 
      SET @SQL = ''EXEC ' + quotename(@AuditSchema) + '.pAutoAuditRebuild @SchemaName = '''''' + @Schema + '''''', @TableName = '''''' + @Object + ''''''''
      EXEC (@SQL)
    END    
  IF @EventType = ''DROP_TABLE''
    BEGIN 
      SET @SQL = ''EXEC ' + quotename(@AuditSchema) + '.pAutoAuditDrop @SchemaName = '''''' + @Schema + '''''', @TableName = '''''' + @Object + ''''''''
      EXEC (@SQL)
    END    
END   
'
EXEC (@SchemaSQL)


go --------------------------------------------------------------------

--**************** Setup Script Section #6 ****************
-- Create Views
--*********************************************************

Print 'Creating View - vAuditArchive (view for Archive Audit table)'
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

SET @SchemaSQL = 'CREATE VIEW ' + quotename(@AuditSchema) + '.[vAuditArchive]' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns data from the Archive AutoAudit tables. ' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SELECT	AH.[AuditHeaderID] as AuditID' + Char(13) + Char(10)
       + '			,AH.[AuditDate]' + Char(13) + Char(10)
       + '			,AH.[HostName]' + Char(13) + Char(10)
       + '			,AH.[SysUser]' + Char(13) + Char(10)
       + '			,AH.[Application]' + Char(13) + Char(10)
       + '			,AH.[TableName]' + Char(13) + Char(10)
       + '			,AH.[Operation]' + Char(13) + Char(10)
       + '			,AH.[SQLStatement]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey2]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey3]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey4]' + Char(13) + Char(10)
       + '			,AH.[PrimaryKey5]' + Char(13) + Char(10)
       + '			,AH.[RowDescription]' + Char(13) + Char(10)
       + '			,AH.[SecondaryRow]' + Char(13) + Char(10)
       + '			,AD.[ColumnName]' + Char(13) + Char(10)
       + '			,AD.[OldValue]' + Char(13) + Char(10)
       + '			,AD.[NewValue]' + Char(13) + Char(10)
       + '			,AH.[RowVersion]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditHeaderArchive] AH' + Char(13) + Char(10)
       + 'LEFT JOIN ' + quotename(@AuditSchema) + '.[AuditDetailArchive] AD' + Char(13) + Char(10)
       + '	ON		AH.[AuditHeaderID] = AD.[AuditHeaderID];' + Char(13) + Char(10)
EXEC (@SchemaSQL)

go --------------------------------------------------------------------
Print 'Creating View - vAuditAll'
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

SET @SchemaSQL = 'CREATE VIEW ' + quotename(@AuditSchema) + '.[vAuditAll]' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns data from the Active and Archive AutoAudit tables. ' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SELECT	cast(''Active'' as varchar(7)) as Source, * '
       + 'FROM		' + quotename(@AuditSchema) + '.[vAudit] vA' + Char(13) + Char(10)
       + 'UNION All ' + Char(13) + Char(10)
       + 'SELECT	cast(''Archive'' as varchar(7)) as Source, * '
       + 'FROM		' + quotename(@AuditSchema) + '.[vAuditArchive] vAA;' + Char(13) + Char(10)

EXEC (@SchemaSQL)
 
go --------------------------------------------------------------------
Print 'Creating View - vAuditHeaderAll'
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

SET @SchemaSQL = 'CREATE VIEW ' + quotename(@AuditSchema) + '.[vAuditHeaderAll]' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10)
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns data from the AuditHeader and AuditHeaderArchive AutoAudit tables. ' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SELECT	cast(''Active'' as varchar(7)) as Source ' + Char(13) + Char(10)
       + '			,[AuditHeaderID]' + Char(13) + Char(10)
       + '			,[AuditDate]' + Char(13) + Char(10)
       + '			,[HostName]' + Char(13) + Char(10)
       + '			,[SysUser]' + Char(13) + Char(10)
       + '			,[Application]' + Char(13) + Char(10)
       + '			,[TableName]' + Char(13) + Char(10)
       + '			,[Operation]' + Char(13) + Char(10)
       + '			,[SQLStatement]' + Char(13) + Char(10)
       + '			,[PrimaryKey]' + Char(13) + Char(10)
       + '			,[PrimaryKey2]' + Char(13) + Char(10)
       + '			,[PrimaryKey3]' + Char(13) + Char(10)
       + '			,[PrimaryKey4]' + Char(13) + Char(10)
       + '			,[PrimaryKey5]' + Char(13) + Char(10)
       + '			,[RowDescription]' + Char(13) + Char(10)
       + '			,[SecondaryRow]' + Char(13) + Char(10)
       + '			,[RowVersion]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditHeader] AH' + Char(13) + Char(10)
       + 'UNION All ' + Char(13) + Char(10)
       + 'SELECT	cast(''Archive'' as varchar(7)) as Source ' + Char(13) + Char(10)
       + '			,[AuditHeaderID]' + Char(13) + Char(10)
       + '			,[AuditDate]' + Char(13) + Char(10)
       + '			,[HostName]' + Char(13) + Char(10)
       + '			,[SysUser]' + Char(13) + Char(10)
       + '			,[Application]' + Char(13) + Char(10)
       + '			,[TableName]' + Char(13) + Char(10)
       + '			,[Operation]' + Char(13) + Char(10)
       + '			,[SQLStatement]' + Char(13) + Char(10)
       + '			,[PrimaryKey]' + Char(13) + Char(10)
       + '			,[PrimaryKey2]' + Char(13) + Char(10)
       + '			,[PrimaryKey3]' + Char(13) + Char(10)
       + '			,[PrimaryKey4]' + Char(13) + Char(10)
       + '			,[PrimaryKey5]' + Char(13) + Char(10)
       + '			,[RowDescription]' + Char(13) + Char(10)
       + '			,[SecondaryRow]' + Char(13) + Char(10)
       + '			,[RowVersion]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditHeaderArchive] AHA;' + Char(13) + Char(10)

EXEC (@SchemaSQL)
 
go --------------------------------------------------------------------
Print 'Creating View - vAuditDetailAll'
DECLARE @SchemaSQL NVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'

SET @SchemaSQL = 'CREATE VIEW ' + quotename(@AuditSchema) + '.[vAuditDetailAll]' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns data from the AuditDetail and AuditDetailArchive AutoAudit tables. ' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SELECT	cast(''Active'' as varchar(7)) as Source ' + Char(13) + Char(10)
       +			',[AuditDetailID]' + Char(13) + Char(10)
       +			',[AuditHeaderID]' + Char(13) + Char(10)
       +			',[ColumnName]' + Char(13) + Char(10)
       +			',[OldValue]' + Char(13) + Char(10)
       +			',[NewValue]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditDetail] AD' + Char(13) + Char(10)
       + 'UNION All ' + Char(13) + Char(10)
       + 'SELECT	cast(''Archive'' as varchar(7)) as Source ' + Char(13) + Char(10)
       +			',[AuditDetailID]' + Char(13) + Char(10)
       +			',[AuditHeaderID]' + Char(13) + Char(10)
       +			',[ColumnName]' + Char(13) + Char(10)
       +			',[OldValue]' + Char(13) + Char(10)
       +			',[NewValue]' + Char(13) + Char(10)
       + 'FROM		' + quotename(@AuditSchema) + '.[AuditDetailArchive] ADA;' + Char(13) + Char(10)

EXEC (@SchemaSQL)

go --------------------------------------------------------------------
Print 'Creating Stored Procedure - pAutoAuditArchive'
DECLARE @SchemaSQL nVARCHAR(max)
DECLARE @AuditSchema VARCHAR(50)	
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'
DECLARE @Version VARCHAR(5)	
SELECT @Version = [SettingValue] from #Settings where [SettingName] = 'Version'
DECLARE @WithLogFlag BIT
SELECT @WithLogFlag = [SettingValue] from #Settings where [SettingName] = 'WithLogFlag'

SET @SchemaSQL = 'CREATE PROC ' + quotename(@AuditSchema) + '.[pAutoAuditArchive]' + Char(13) + Char(10)
       + '(' + Char(13) + Char(10) 
       + '@ArchiveAfterNumberOfDays int = -1 --the number of days after which the audit data will be archived. (-1 means use setting from AuditSettings table.)' + Char(13) + Char(10) 
       + ',@DeleteAfterNumberOfDays int = -1 --the number of days after which the audit data will be deleted from the archive (or active) table. (-1 means use setting from AuditSettings table.)' + Char(13) + Char(10) 
       + ',@KeepLastEntry bit = 1 --The last Audit entry is not archived (even if it should based on dates) to ensure a sequential RowVersion is produced.' + Char(13) + Char(10) 
       + ')' + Char(13) + Char(10) 
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10) 
       + ' -- This SP moves Audit data from the active tables to the archive tables ' + Char(13) + Char(10)
       + ' -- and deletes Audit data older than the specified retention period. ' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'SET NoCount ON' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' Begin Try ' + Char(13) + Char(10)

       + '	--PROCESS INPUT PARAMETERS' + Char(13) + Char(10)
       + '	--Archive Audit data older than (days)' + Char(13) + Char(10)
       + '	If 	ISNULL(@ArchiveAfterNumberOfDays,-1) <= -1' + Char(13) + Char(10)
       + '		BEGIN' + Char(13) + Char(10)
       + '			--get the setting from AuditSettings' + Char(13) + Char(10)
       + '			SELECT	@ArchiveAfterNumberOfDays = cast(SettingValue as integer)' + Char(13) + Char(10)
       + '			FROM	' + quotename(@AuditSchema) + '.[AuditSettings]' + Char(13) + Char(10)
       + '			WHERE	SettingName = ''Archive Audit data older than (days)''' + Char(13) + Char(10)
       + '		END' + Char(13) + Char(10)  + Char(13) + Char(10)

       + '	--Delete Audit data older than (days)' + Char(13) + Char(10)
       + '	If 	ISNULL(@DeleteAfterNumberOfDays,-1) <= -1' + Char(13) + Char(10)
       + '		BEGIN' + Char(13) + Char(10)
       + '			--get the setting from AuditSettings' + Char(13) + Char(10)
       + '			SELECT	@DeleteAfterNumberOfDays = cast(SettingValue as integer)' + Char(13) + Char(10)
       + '			FROM	' + quotename(@AuditSchema) + '.[AuditSettings]' + Char(13) + Char(10)
       + '			WHERE	SettingName = ''Delete Audit data older than (days)''' + Char(13) + Char(10)
       + '		END' + Char(13) + Char(10)  + Char(13) + Char(10)

       + 'Declare @MinNumberOfDays int' + Char(13) + Char(10)
       + 'SET @MinNumberOfDays = @ArchiveAfterNumberOfDays' + Char(13) + Char(10)
       + 'If @DeleteAfterNumberOfDays < @ArchiveAfterNumberOfDays' + Char(13) + Char(10)
       + '	SET @MinNumberOfDays = @DeleteAfterNumberOfDays' + Char(13) + Char(10) + Char(13) + Char(10)
	
       + '--Start by deleting archive data as requested' + Char(13) + Char(10)
       + 'Print ''Delete Archive''' + Char(13) + Char(10)
       + 'DELETE	FROM	' + quotename(@AuditSchema) + '.[AuditDetailArchive]' + Char(13) + Char(10) 
       + 'WHERE	AuditHeaderID in (	SELECT	AuditHeaderID' + Char(13) + Char(10)
       + '							FROM	' + quotename(@AuditSchema) + '.[AuditHeaderArchive]' + Char(13) + Char(10) 
       + '							WHERE	AuditDate < DATEADD(day, @DeleteAfterNumberOfDays * -1, getdate()));' + Char(13) + Char(10) + Char(13) + Char(10)

       + '--disable FK' + Char(13) + Char(10) 
       + 'ALTER TABLE ' + quotename(@AuditSchema) + '.[AuditDetailArchive] NOCHECK CONSTRAINT fkAuditHeaderArchive' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'DELETE	FROM	' + quotename(@AuditSchema) + '.[AuditHeaderArchive]' + Char(13) + Char(10) 
       + 'WHERE	AuditDate < DATEADD(day, @DeleteAfterNumberOfDays * -1, getdate());' + Char(13) + Char(10) + Char(13) + Char(10)

       + '--enable FK' + Char(13) + Char(10) 
       + 'ALTER TABLE ' + quotename(@AuditSchema) + '.[AuditDetailArchive] CHECK CONSTRAINT fkAuditHeaderArchive' + Char(13) + Char(10) + Char(13) + Char(10)

        + 'Print ''Move to Archive''' + Char(13) + Char(10)
       + '--Don''t bother archiving active if the delete period is <= to the archive period' + Char(13) + Char(10)
       + 'If NOT @DeleteAfterNumberOfDays <= @ArchiveAfterNumberOfDays' + Char(13) + Char(10)
       + '	BEGIN' + Char(13) + Char(10)
       + '		--copy from  [AuditHeader] to [AuditHeaderArchive]' + Char(13) + Char(10)
       + '		INSERT ' + quotename(@AuditSchema) + '.[AuditHeaderArchive]' + Char(13) + Char(10) 
       + '		Select * FROM ' + quotename(@AuditSchema) + '.[AuditHeader]' + Char(13) + Char(10)
       + '		WHERE	AuditDate < Dateadd(day, @ArchiveAfterNumberOfDays * -1, getdate())' + Char(13) + Char(10)
       + '		AND		AuditHeaderID not in ' + Char(13) + Char(10) 
       + '		(Select max(AuditHeaderID) from ' + quotename(@AuditSchema) + '.AuditHeader ' + Char(13) + Char(10)
       + '		where @KeepLastEntry = 1 ' + Char(13) + Char(10)
       + '		group by TableName, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5);' + Char(13) + Char(10) + Char(13) + Char(10)
       + '		--copy from  [AuditDetail] to [AuditDetailArchive]' + Char(13) + Char(10)
       + '		INSERT ' + quotename(@AuditSchema) + '.[AuditDetailArchive]' + Char(13) + Char(10) 
       + '		SELECT * FROM ' + quotename(@AuditSchema) + '.[AuditDetail]' + Char(13) + Char(10)
       + '		WHERE	AuditHeaderID in (	SELECT	AuditHeaderID' + Char(13) + Char(10)
       + '							FROM	' + quotename(@AuditSchema) + '.[AuditHeader]' + Char(13) + Char(10) 
       + '							WHERE	AuditDate < Dateadd(day, @ArchiveAfterNumberOfDays * -1, getdate())' + Char(13) + Char(10)
       + '							EXCEPT' + Char(13) + Char(10) 
       + '							Select max(AuditHeaderID) from ' + quotename(@AuditSchema) + '.[AuditHeader] ' + Char(13) + Char(10)
       + '							where @KeepLastEntry = 1 ' + Char(13) + Char(10)
       + '							group by TableName, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5);' + Char(13) + Char(10) + Char(13) + Char(10)
       + '	END' + Char(13) + Char(10) + Char(13) + Char(10)

 SET @SchemaSQL = @SchemaSQL + 'Print ''Delete Active''' + Char(13) + Char(10)
       + '--NOW delete from [AuditDetail] and [AuditHeader]' + Char(13) + Char(10)
       + '--delete Active data' + Char(13) + Char(10)
       + 'DELETE	FROM	' + quotename(@AuditSchema) + '.[AuditDetail]' + Char(13) + Char(10) 
       + 'WHERE	AuditHeaderID in (	SELECT	AuditHeaderID' + Char(13) + Char(10)
       + '							FROM	' + quotename(@AuditSchema) + '.[AuditHeader]' + Char(13) + Char(10) 
       + '							WHERE	AuditDate < DATEADD(day, @MinNumberOfDays * -1, getdate())' + Char(13) + Char(10)
       + '							EXCEPT' + Char(13) + Char(10) 
       + '							Select max(AuditHeaderID) from ' + quotename(@AuditSchema) + '.AuditHeader ' + Char(13) + Char(10)
       + '							where @KeepLastEntry = 1 ' + Char(13) + Char(10)
       + '							group by TableName, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5);' + Char(13) + Char(10) + Char(13) + Char(10)
       + '--disable FK' + Char(13) + Char(10) 
       + 'ALTER TABLE ' + quotename(@AuditSchema) + '.[AuditDetail] NOCHECK CONSTRAINT fkAuditHeader' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'DELETE	FROM	' + quotename(@AuditSchema) + '.[AuditHeader]' + Char(13) + Char(10) 
       + 'WHERE	AuditDate < DATEADD(day, @MinNumberOfDays * -1, getdate())' + Char(13) + Char(10)
       + '		AND		AuditHeaderID not in ' + Char(13) + Char(10) 
       + '		(Select max(AuditHeaderID) from ' + quotename(@AuditSchema) + '.AuditHeader ' + Char(13) + Char(10)
       + '		where @KeepLastEntry = 1 ' + Char(13) + Char(10)
       + '		group by TableName, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5);' + Char(13) + Char(10) + Char(13) + Char(10)

       + '--disable FK' + Char(13) + Char(10) 
       + 'ALTER TABLE ' + quotename(@AuditSchema) + '.[AuditDetail] CHECK CONSTRAINT fkAuditHeader' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' End Try ' + Char(13) + Char(10)
       + ' Begin Catch ' + Char(13) + Char(10)
       + '   DECLARE @ErrorMessage NVARCHAR(4000), @ErrorSeverity INT, @ErrorState INT, @ErrorLine INT;' + Char(13) + Char(10) 

       + '   SET @ErrorMessage = ERROR_MESSAGE();  ' + Char(13) + Char(10)
       + '   SET @ErrorSeverity = ERROR_SEVERITY(); ' + Char(13) + Char(10) 
       + '   SET @ErrorState = ERROR_STATE();  ' + Char(13) + Char(10)
       + '   SET @ErrorLine = ERROR_LINE();  ' + Char(13) + Char(10)
       + '   RAISERROR(@ErrorMessage,@ErrorSeverity,@ErrorState)' + case when @WithLogFlag = 1 then ' with log;' else ';' end + Char(13) + Char(10) 
       + '   PRINT ''Error Line: '' + cast(@ErrorLine as varchar);' + Char(13) + Char(10)
       + ' End Catch '

EXEC (@SchemaSQL)

go --------------------------------------------------------------------

--**************** Setup Script Section #7 ****************
-- Create pAutoAudit
--*********************************************************

Print 'Creating Stored Procedure - pAutoAudit'
go
CREATE PROC pAutoAudit 
	(
	@SchemaName			sysname		= 'dbo',--this is the default schema name for the tables getting AutoAudit added
	@TableName			sysname,			--enter the name of the table to add AutoAudit to.
	@ColumnNames		varchar(max)= '<All>',  --columns to include when logging details (@Log...=2). Default = '<All>'. Format: '[Col1],[Col2],...'
	@StrictUserContext	bit			= 1,    -- 2.00 if 0 then permits DML setting of Created, CreatedBy, Modified, ModifiedBy
	@LogSQL				bit			= 0,	-- 0 = Don't log SQL statement in AuditHeader, 1 = log the SQL statement
	@BaseTableDDL		bit			= 0,	-- 0 = don't add audit columns to base table, 1 = add audit columns to base table
	@LogInsert			tinyint		= 2,	-- 0 = nothing, 1 = header only, 2 = header and detail
	@LogUpdate			tinyint		= 2,	-- 0 = nothing, 1 = header only, 2 = header and detail
	@LogDelete			tinyint		= 2		-- 0 = nothing, 1 = header only, 2 = header and detail
	) with recompile
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to add AutoAudit to a specified table.

SET NoCount ON
 
DECLARE @SQL NVARCHAR(max),
		@SQLColumns NVARCHAR(max),
		@Version VARCHAR(5),
		@AuditSchema VARCHAR(50),
		@ViewSchema VARCHAR(50),
		@RowHistoryViewScope VARCHAR(20),
		@DeletedViewScope VARCHAR(20),
		@AddExtendedProperties VARCHAR(1),
		@CreatedColumnName sysname,
		@CreatedByColumnName sysname,
		@ModifiedColumnName sysname,
		@ModifiedByColumnName sysname,
		@RowVersionColumnName sysname,
		@CreateDeletedView bit,
		@CreateRowHistoryView bit,
		@CreateRowHistoryFunction bit,
		@CreateTableRecoveryFunction bit,
		@WithLogFlag bit,
		@DateStyle VARCHAR(3),
		@ViewPrefix varchar(10),
		@UDFPrefix varchar(10),
		@RowHistoryViewSuffix varchar(20),
		@DeletedViewSuffix varchar(20),
		@RowHistoryFunctionSuffix varchar(20),
		@TableRecoveryFunctionSuffix varchar(20)

--get the schema for the AutoAudit objects
--*********************************************************************************
Set @AuditSchema = null		--set this manually if you have more than one instance 
							--of AutoAudit objects in the database. Otherwise leave 
							--it set to null
--*********************************************************************************
If @AuditSchema is null
	Begin
		If (Select count(*) from sys.objects where name='AuditSettings' and [type] ='U') > 1
			Begin
				Raiserror ('There is more than 1 instance of AutoAudit in this db. @AuditSchema MUST be set manually in the pAutoAudit Stored Procedure.',16,0)
				Return
			End
		Else
			SELECT @AuditSchema = Schema_name(schema_id) from sys.objects where [name]='AuditSettings' and [type] ='U'
	End

--get [AuditSettings] - @Version
Select	@SQL = 'SELECT @SettingValue = [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Version'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @Version OUTPUT

--get [AuditSettings] - @ViewSchema
Select	@SQL = 'SELECT @SettingValue = [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Schema for _RowHistory and _Deleted objects'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @ViewSchema OUTPUT
If @ViewSchema = '<TableSchema>' Set @ViewSchema = @SchemaName

--get [AuditSettings] - @DateStyle
Select	@SQL = 'SELECT @SettingValue = [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''DateStyle'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @DateStyle OUTPUT
If isnull(@DateStyle,'') not in ('113','121') Set @DateStyle = '113'

--get [AuditSettings] - @RowHistoryViewScope
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''Active'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''RowHistory View Scope'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @RowHistoryViewScope OUTPUT
If isnull(@RowHistoryViewScope,'') not in ('Active','Archive','All') Set @RowHistoryViewScope = 'Active'

--get [AuditSettings] - @DeletedViewScope
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''Active'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Deleted View Scope'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @DeletedViewScope OUTPUT
If isnull(@DeletedViewScope,'') not in ('Active','Archive','All') Set @DeletedViewScope = 'Active'

--get [AuditSettings] - @AddExtendedProperties
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''1'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Add Extended Properties Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @AddExtendedProperties OUTPUT

--get [AuditSettings] - @CreatedColumnName
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''Created'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''CreatedColumnName'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreatedColumnName OUTPUT

--get [AuditSettings] - @CreatedByColumnName
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''CreatedBy'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''CreatedByColumnName'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreatedByColumnName OUTPUT

--get [AuditSettings] - @ModifiedColumnName
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''Modified'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''ModifiedColumnName'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @ModifiedColumnName OUTPUT

--get [AuditSettings] - @ModifiedByColumnName
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''ModifiedBy'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''ModifiedByColumnName'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @ModifiedByColumnName OUTPUT

--get [AuditSettings] - @RowVersionColumnName
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''RowVersion'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''RowVersionColumnName'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @RowVersionColumnName OUTPUT

--get [AuditSettings] - @ViewPrefix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''v'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''ViewPrefix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @ViewPrefix OUTPUT
Select @ViewPrefix = isnull(LTRIM(RTRIM(@ViewPrefix)),'')

--get [AuditSettings] - @UDFPrefix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],'''') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''UDFPrefix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @UDFPrefix OUTPUT
Select @UDFPrefix = isnull(LTRIM(RTRIM(@UDFPrefix)),'')

--get [AuditSettings] - @RowHistoryViewSuffix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],'''') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''RowHistoryViewSuffix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @RowHistoryViewSuffix OUTPUT
Select @RowHistoryViewSuffix = isnull(LTRIM(RTRIM(@RowHistoryViewSuffix)),'_RowHistory')

--get [AuditSettings] - @DeletedViewSuffix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],'''') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''DeletedViewSuffix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @DeletedViewSuffix OUTPUT
Select @DeletedViewSuffix = isnull(LTRIM(RTRIM(@DeletedViewSuffix)),'_Deleted')

--get [AuditSettings] - @RowHistoryFunctionSuffix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],'''') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''RowHistoryFunctionSuffix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @RowHistoryFunctionSuffix OUTPUT
Select @RowHistoryFunctionSuffix = isnull(LTRIM(RTRIM(@RowHistoryFunctionSuffix)),'_RowHistory')

--get [AuditSettings] - @TableRecoveryFunctionSuffix
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],'''') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''TableRecoveryFunctionSuffix'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @TableRecoveryFunctionSuffix OUTPUT
Select @TableRecoveryFunctionSuffix = isnull(LTRIM(RTRIM(@TableRecoveryFunctionSuffix)),'_TableRecovery')

--get [AuditSettings] - @CreateDeletedView
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''1'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Default _Deleted view Creation Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreateDeletedView OUTPUT

--get [AuditSettings] - @CreateRowHistoryView
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''1'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Default _RowHistory view Creation Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreateRowHistoryView OUTPUT

--get [AuditSettings] - @CreateRowHistoryFunction
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''1'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Default _RowHistory function Creation Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreateRowHistoryFunction OUTPUT

--get [AuditSettings] - @CreateTableRecoveryFunction
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''1'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Default _TableRecovery function Creation Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @CreateTableRecoveryFunction OUTPUT

--get [AuditSettings] - @WithLogFlag
Select	@SQL = 'SELECT @SettingValue = isnull([SettingValue],''0'') from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Raiserror to Windows Log Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @WithLogFlag OUTPUT

-- script to create autoAudit triggers
declare @PKColumnNameList varchar(1024)
declare @PKColumnNameConcatenationWithQuotename varchar(1024)
declare @PKColumnNameListIfUpdate varchar(1024)
declare @RowHistoryUDFFilter varchar(1024)
declare @PKColumnNameConcatenationWithQuotenameAndDateConvert varchar(1024)
declare @PKColumnNameListWithDateConvert varchar(1024)
declare @PKColumnsForDeletedView varchar(1024)
declare @PKColumnQty smallint

set @PKColumnNameList = ''
set @PKColumnNameConcatenationWithQuotename = ''
set @PKColumnNameListIfUpdate = ''
set @RowHistoryUDFFilter = 'WHERE		'
set @PKColumnNameConcatenationWithQuotenameAndDateConvert = ''
set @PKColumnNameListWithDateConvert = ''
set @PKColumnsForDeletedView = ''
set @PKColumnQty = 0

--get PK Columns
select		@PKColumnNameConcatenationWithQuotename = @PKColumnNameConcatenationWithQuotename + 'quotename(' + 'src.[' + c.name + ']) + '
			,@PKColumnNameList = @PKColumnNameList + '[' + c.name + '],'
			,@PKColumnNameConcatenationWithQuotenameAndDateConvert = @PKColumnNameConcatenationWithQuotenameAndDateConvert + 'quotename(' + 'convert(varchar(36),src.[' + c.name + '],' + @DateStyle + ')) + '
			,@PKColumnNameListWithDateConvert = @PKColumnNameListWithDateConvert + 'convert(varchar(36),src.[' + c.name + '],' + @DateStyle + '), '
			,@PKColumnNameListIfUpdate = @PKColumnNameListIfUpdate + 'update ([' + c.name + ']) or '
			,@RowHistoryUDFFilter = @RowHistoryUDFFilter + '[' + c.name + '] = @PK' + isnull(nullif(cast(@PKColumnQty + 1 as varchar(1)),1), '') + ' AND '
			,@PKColumnsForDeletedView = @PKColumnsForDeletedView + '		,PivotData.PrimaryKey' + isnull(nullif(cast(@PKColumnQty + 1 as varchar(1)),1), '') + ' as [' + c.name + ']' + Char(13) + Char(10)
			,@PKColumnQty = @PKColumnQty + 1
from		sys.tables t
inner join	sys.schemas s
	on		s.schema_id = t.schema_id
inner join	sys.indexes i
	on		t.object_id = i.object_id
inner join	sys.index_columns ic
	on		i.object_id = ic.object_id
	and		i.index_id = ic.index_id
inner join	sys.columns c
	on		ic.object_id = c.object_id
	and		ic.column_id = c.column_id
inner join	sys.types as ty
	on		ty.user_type_id = c.user_type_id
where		i.is_primary_key = 1 
	AND		t.name = @TableName 
	AND		s.name = @SchemaName
    AND		ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')

select @PKColumnNameConcatenationWithQuotename = reverse(substring(reverse(@PKColumnNameConcatenationWithQuotename),4,1024))
select @PKColumnNameListIfUpdate = 'if ' + reverse(substring(reverse(@PKColumnNameListIfUpdate),4,1024))
select @RowHistoryUDFFilter = reverse(substring(reverse(@RowHistoryUDFFilter),5,1024))
select @PKColumnNameConcatenationWithQuotenameAndDateConvert = reverse(substring(reverse(@PKColumnNameConcatenationWithQuotenameAndDateConvert),4,1024))
select @PKColumnNameListWithDateConvert = reverse(substring(reverse(@PKColumnNameListWithDateConvert),3,1024))
select @PKColumnsForDeletedView = reverse(substring(reverse('		'+ substring(@PKColumnsForDeletedView,4,1024)),3,1024))

-- Table no-PK Check  
  IF @PKColumnQty = 0
  BEGIN 
    PRINT '*** ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' invalid Table - no Primary Key or invalid Primary Key data type. No triggers created.' + Char(13) + Char(10) + Char(13) + Char(10)
    RETURN
  END  
   
-- Table HierarchyID-PK Check  
  IF exists (select 1
  from sys.tables t
    join sys.schemas s
      on s.schema_id = t.schema_id
    join sys.indexes i
      on t.object_id = i.object_id
    join sys.index_columns ic
  	  on i.object_id = ic.object_id
      and i.index_id = ic.index_id
    join sys.columns c
      on ic.object_id = c.object_id
      and ic.column_id = c.column_id
	join sys.types as ty
	  on ty.user_type_id = c.user_type_id
  where i.is_primary_key = 1 AND t.name = @TableName AND s.name = @SchemaName AND ty.name = 'HierarchyID')
  BEGIN 
    PRINT '*** ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' HierarchyID PK. No triggers created.' + Char(13) + Char(10)
    RETURN
  END  

IF @StrictUserContext = 0 AND @BaseTableDDL = 0 
  BEGIN 
    RAISERROR('@StrictUserContext = 0 requires  @BaseTableDDL = 1. No triggers created.' , 16,1)
    RETURN 
  END  

--set the context info to bypass ddl trigger
Set context_info 0x1;

PRINT 'Creating AutoAudit for table: ' + quotename(@SchemaName) + '.' + quotename(@TableName) 
PRINT '	Options:  @StrictUserContext=' + isnull(cast(@StrictUserContext as varchar),'<null>') +
				', @LogSQL=' + isnull(cast(@LogSQL as varchar),'<null>') +
				', @BaseTableDDL=' + isnull(cast(@BaseTableDDL as varchar),'<null>') +
				', @LogInsert=' + isnull(cast(@LogInsert as varchar),'<null>') +
				', @LogUpdate=' + isnull(cast(@LogUpdate as varchar),'<null>') +
				', @LogDelete=' + isnull(cast(@LogDelete as varchar),'<null>') +
				', @AuditSchema=''' + isnull(@AuditSchema,'<null>') + '''' +
				', @ColumnNames=''' + isnull(@ColumnNames,'<null>') + ''''
 
PRINT '	Dropping existing AutoAudit components'

--Create temp table for ViewSchema of existing objects
Create table #ViewSchema (ViewSchema sysname)

declare @DeletedViewSchema sysname
Select @DeletedViewSchema = isnull((Select ViewSchema from #ViewSchema),@ViewSchema)

-- drop existing insert trigger
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @SchemaName + ''''
       + '   and o.name = ''' + @TableName + '_Audit_Insert' + ''' )'
       + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert')
EXEC (@SQL)

-- drop existing update trigger
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @SchemaName + ''''
       + '   and o.name = ''' + @TableName + '_Audit_Update' + ''' )'
       + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update')
EXEC (@SQL)

-- drop existing delete trigger
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @SchemaName + ''''
       + '   and o.name = ''' + @TableName + '_Audit_Delete' + ''' )'
       + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete')
EXEC (@SQL)

-- drop existing _Deleted view for the new view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @DeletedViewSchema + ''''
       + '   and o.name = ''' + @ViewPrefix + @TableName + @DeletedViewSuffix + ''' )'
       + ' DROP VIEW ' + quotename(@DeletedViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @DeletedViewSuffix)
EXEC (@SQL)

-- drop existing _RowHistory view for the new view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @DeletedViewSchema + ''''
       + '   and o.name = ''' + @ViewPrefix + @TableName + @RowHistoryViewSuffix + ''' )'
       + ' DROP VIEW ' + quotename(@DeletedViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix)
EXEC (@SQL)

-- drop existing _RowHistory UDF for the new view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @DeletedViewSchema + ''''
       + '   and o.name = ''' + @UDFPrefix + @TableName + @RowHistoryFunctionSuffix + ''' )'
       + ' DROP FUNCTION ' + quotename(@DeletedViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @RowHistoryFunctionSuffix)
EXEC (@SQL)

-- drop existing _TableRecovery UDF for the new view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @DeletedViewSchema + ''''
       + '   and o.name = ''' + @UDFPrefix + @TableName + @TableRecoveryFunctionSuffix + ''' )'
       + ' DROP FUNCTION ' + quotename(@DeletedViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @TableRecoveryFunctionSuffix)
EXEC (@SQL)

-- drop existing _Deleted view for the old view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @ViewSchema + ''''
       + '   and o.name = ''' + @ViewPrefix + @TableName + @DeletedViewSuffix + ''' )'
       + ' DROP VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @DeletedViewSuffix)
EXEC (@SQL)

-- drop existing _RowHistory view for the old view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @ViewSchema + ''''
       + '   and o.name = ''' + @ViewPrefix + @TableName + @RowHistoryViewSuffix + ''' )'
       + ' DROP VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix)
EXEC (@SQL)

-- drop existing _RowHistory UDF for the old view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @ViewSchema + ''''
       + '   and o.name = ''' + @UDFPrefix + @TableName + @RowHistoryFunctionSuffix + ''' )'
       + ' DROP FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @RowHistoryFunctionSuffix)
EXEC (@SQL)

-- drop existing _TableRecovery UDF for the old view schema
SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
       + ' where s.name = ''' + @ViewSchema + ''''
       + '   and o.name = ''' + @UDFPrefix + @TableName + @TableRecoveryFunctionSuffix + ''' )'
       + ' DROP FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @TableRecoveryFunctionSuffix)
EXEC (@SQL)

IF @BaseTableDDL = 1 
  BEGIN 
	Print '	Adding Base Table DDL'
    -- add Created column 
    IF not exists (select *
			      from sys.tables t
				    join sys.schemas s
				      on s.schema_id = t.schema_id
				    join sys.columns c
				      on t.object_id = c.object_id
			      where  t.name = @TableName AND s.name = @SchemaName and c.name = @CreatedColumnName)
      BEGIN -- is this default causing an issue? 
        IF @StrictUserContext = 1                                                                                        
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @CreatedColumnName + ' DateTime NOT NULL Constraint ' + quotename(@TableName + '_' + @CreatedColumnName + '_df') + ' Default GetDate()' + Char(13) + Char(10)
        ELSE   
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @CreatedColumnName + ' DateTime NULL Constraint ' + quotename(@TableName + '_' + @CreatedColumnName + '_df') + ' Default GetDate()' + Char(13) + Char(10)
		  --add extended property
		  If @AddExtendedProperties = '1'
				SET @SQL = @SQL + 'EXEC sys.sp_addextendedproperty 
				  @level0type = N''SCHEMA'', @level0name = N''' + @SchemaName + ''',
				  @level1type = N''TABLE'',  @level1name = N''' + @TableName + ''',
				  @level2type = N''COLUMN'', @level2name = N''' + @CreatedColumnName + ''',
				  @name = N''MS_Description'', @value = N''Column added by AutoAudit'''
        EXEC (@SQL)
      END

    -- add CreatedBy column 
    IF not exists (select *
			      from sys.tables t
				    join sys.schemas s
				      on s.schema_id = t.schema_id
				    join sys.columns c
				      on t.object_id = c.object_id
			      where  t.name = @TableName AND s.name = @SchemaName and c.name = + @CreatedByColumnName)
      BEGIN 
        IF @StrictUserContext = 1                                                                                        
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @CreatedByColumnName + ' NVARCHAR(128) NOT NULL Constraint ' + quotename(@TableName + '_' + @CreatedByColumnName + '_df') + ' Default(Suser_SName())' + Char(13) + Char(10)
        ELSE   
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @CreatedByColumnName + ' NVARCHAR(128) NULL Constraint ' + quotename(@TableName + '_' + @CreatedByColumnName + '_df') + ' Default(Suser_SName())' + Char(13) + Char(10)
		  --add extended property
		  If @AddExtendedProperties = '1'
			  SET @SQL = @SQL + 'EXEC sys.sp_addextendedproperty 
				@level0type = N''SCHEMA'', @level0name = N''' + @SchemaName + ''',
				@level1type = N''TABLE'',  @level1name = N''' + @TableName + ''',
				@level2type = N''COLUMN'', @level2name = N''' + @CreatedByColumnName + ''',
				@name = N''MS_Description'', @value = N''Column added by AutoAudit'''
        EXEC (@SQL)
      END

    -- add Modified column 
    IF not exists( select *
			      from sys.tables t
				    join sys.schemas s
				      on s.schema_id = t.schema_id
				    join sys.columns c
				      on t.object_id = c.object_id
			      where  t.name = @TableName AND s.name = @SchemaName and c.name = @ModifiedColumnName)
      BEGIN                                                                                               
        IF @StrictUserContext = 1                                                                                        
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @ModifiedColumnName + ' DateTime NOT NULL Constraint ' + quotename(@TableName + '_' + @ModifiedColumnName + '_df') + ' Default GetDate()' + Char(13) + Char(10)
        ELSE   
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @ModifiedColumnName + ' DateTime NULL Constraint ' + quotename(@TableName + '_' + @ModifiedColumnName + '_df') + ' Default GetDate()' + Char(13) + Char(10)
 		  --add extended property
		  If @AddExtendedProperties = '1'
			  SET @SQL = @SQL + 'EXEC sys.sp_addextendedproperty 
				@level0type = N''SCHEMA'', @level0name = N''' + @SchemaName + ''',
				@level1type = N''TABLE'',  @level1name = N''' + @TableName + ''',
				@level2type = N''COLUMN'', @level2name = N''' + @ModifiedColumnName + ''',
				@name = N''MS_Description'', @value = N''Column added by AutoAudit'''
       EXEC (@SQL)
      END
      
    -- add ModifiedBy column 
    IF not exists (select *
			      from sys.tables t
				    join sys.schemas s
				      on s.schema_id = t.schema_id
				    join sys.columns c
				      on t.object_id = c.object_id
			      where  t.name = @TableName AND s.name = @SchemaName and c.name = @ModifiedByColumnName)
      BEGIN 
        IF @StrictUserContext = 1                                                                                        
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @ModifiedByColumnName + ' NVARCHAR(128) NOT NULL Constraint ' + quotename(@TableName + '_' + @ModifiedByColumnName + '_df') + ' Default(Suser_SName())' + Char(13) + Char(10)
        ELSE  
          SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @ModifiedByColumnName + ' NVARCHAR(128) NULL Constraint ' + quotename(@TableName + '_' + @ModifiedByColumnName + '_df') + ' Default(Suser_SName())' + Char(13) + Char(10)
  		  --add extended property
		  If @AddExtendedProperties = '1'
			  SET @SQL = @SQL + 'EXEC sys.sp_addextendedproperty 
				@level0type = N''SCHEMA'', @level0name = N''' + @SchemaName + ''',
				@level1type = N''TABLE'',  @level1name = N''' + @TableName + ''',
				@level2type = N''COLUMN'', @level2name = N''' + @ModifiedByColumnName + ''',
				@name = N''MS_Description'', @value = N''Column added by AutoAudit'''
       EXEC (@SQL)
      END  

    -- add RowVersion column 
    IF not exists( select *
			      from sys.tables t
				    join sys.schemas s
				      on s.schema_id = t.schema_id
				    join sys.columns c
				      on t.object_id = c.object_id
			      where  t.name = @TableName AND s.name = @SchemaName and c.name = @RowVersionColumnName)
      BEGIN   
        SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' ADD ' + @RowVersionColumnName + ' INT NULL Constraint ' + quotename(@TableName + '_' + @RowVersionColumnName + '_df') + ' Default 1 WITH VALUES' + Char(13) + Char(10)
  		  --add extended property
		  If @AddExtendedProperties = '1'
			  SET @SQL = @SQL + 'EXEC sys.sp_addextendedproperty 
				@level0type = N''SCHEMA'', @level0name = N''' + @SchemaName + ''',
				@level1type = N''TABLE'',  @level1name = N''' + @TableName + ''',
				@level2type = N''COLUMN'', @level2name = N''' + @RowVersionColumnName + ''',
				@name = N''MS_Description'', @value = N''Column added by AutoAudit'''
        EXEC (@SQL)
      END
      
 END -- @BaseTableDDL = 1     

  
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- build insert trigger 
If @LogInsert > 0
BEGIN
print '	Creating Insert trigger'

SET @SQL = 'CREATE TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert') + ' ON ' + quotename(@SchemaName) + '.' + quotename(@TableName) + Char(13) + Char(10)
       + ' AFTER Insert' + Char(13) + Char(10) + ' NOT FOR REPLICATION AS' + Char(13) + Char(10)
       + ' SET NoCount On ' + Char(13) + Char(10)
       + ' SET ARITHABORT ON ' + Char(13) + Char(10)+ Char(13) + Char(10)
      
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' -- Options: ' + Char(13) + Char(10)
       + ' --   StrictUserContext : ' + CAST(@StrictUserContext as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogSQL            : ' + CAST(@LogSQL as CHAR(1)) + Char(13) + Char(10)
       + ' --   BaseTableDDL      : ' + CAST(@BaseTableDDL as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogInsert         : ' + CAST(@LogInsert as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogUpdate         : ' + CAST(@LogUpdate as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogDelete         : ' + CAST(@LogDelete as CHAR(1)) + Char(13) + Char(10)
       + ' --   ColumnNames       : ' + CAST(@ColumnNames as VARCHAR(1024)) + Char(13) + Char(10) + Char(13) + Char(10)

       + 'DECLARE ' + Char(13) + Char(10)
       + '  @AuditTime DATETIME, ' + Char(13) + Char(10)
       + '  @IsDirty BIT,' + Char(13) + Char(10)
       + '  @DebugFlag BIT,' + Char(13) + Char(10)
       + '  @NestLevel TINYINT' + Char(13) + Char(10)

SELECT @SQL = @SQL 
	+ 'Select @DebugFlag = SettingValue from ' + quotename(@AuditSchema) + '.[AuditSettings] where SettingName = ''Audit Trigger Debug Flag''' + Char(13) + Char(10)
	+ 'Select @NestLevel = TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert') + '''), ''AFTER'', ''DML'')' + Char(13) + Char(10) + Char(13) + Char(10)
    + 'IF @DebugFlag = 1 PRINT ''Firing Insert trigger: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

    + ' -- prevent recursive runs of this trigger' + Char(13) + Char(10)
    + ' IF TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert')+ '''), ''AFTER'', ''DML'') > 1' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''   TRIGGER_NESTLEVEL > 1. Exiting trigger...''' + Char(13) + Char(10)
    + ' 	   return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)

	+ '--get the EnabledFlag setting from the AuditBaseTables table' + Char(13) + Char(10)
	+ 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ ' WHERE [SchemaName] = ''' + @SchemaName + ''''
	+ ' AND [TableName] = ''' + @TableName + ''''
	+ ' AND [EnabledFlag] = 1)' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''AutoAudit EnabledFlag set to "false" for this table in the AuditBaseTables table. Exiting trigger...''' + Char(13) + Char(10)
	+ ' 	return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)
	
       -- keep the variable initialization separate for SQL Server 2005
       + 'SET @AuditTime = GetDate()' + Char(13) + Char(10) + Char(13) + Char(10)
       + 'SET @IsDirty = 0' + Char(13) + Char(10) + Char(13) + Char(10)
       
      + ' set context_info 0x1;' + Char(13) + Char(10)
      + ' Begin Try ' + Char(13) + Char(10)
          
   IF @LogSQL = 1 
     BEGIN  
     	 select @SQL = @SQL
         + ' -- capture SQL Statement' + Char(13) + Char(10)
         + ' DECLARE @ExecStr varchar(50), @UserSQL nvarchar(max)' + Char(13) + Char(10)
         + ' DECLARE  @inputbuffer TABLE' + Char(13) + Char(10) 
         + ' (EventType nvarchar(30), Parameters int, EventInfo nvarchar(max))' + Char(13) + Char(10)
         + ' SET @ExecStr = ''DBCC INPUTBUFFER(@@SPID) with no_infomsgs''' + Char(13) + Char(10)
         + ' INSERT INTO @inputbuffer' + Char(13) + Char(10) 
         + '   EXEC (@ExecStr)' + Char(13) + Char(10)
         + ' SELECT @UserSQL = EventInfo FROM @inputbuffer' + Char(13) + Char(10)
         + Char(13) + Char(10) 
     END

--create a temp table for mapping keys
select @SQL = @SQL
		+ 'Declare @Keys Table (AuditHeaderID BIGINT, 
		PrimaryKey VARCHAR(250), 
		NextRowVersion int default(1))' + Char(13) + Char(10) 
           
-- Insert the AuditHeader row
	select @SQL = @SQL
          + Char(13) + Char(10)
		      + '   INSERT ' + quotename(@AuditSchema) + '.AuditHeader (AuditDate, SysUser, Application, HostName, TableName, Operation, SQLStatement,' + Char(13) + Char(10) 
		      + '			PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, RowDescription, SecondaryRow, [RowVersion])' + Char(13) + Char(10)
		      + '   OUTPUT  inserted.AuditHeaderID, quotename(inserted.PrimaryKey) + isnull(quotename(inserted.PrimaryKey2),'''') + isnull(quotename(inserted.PrimaryKey3),'''') + isnull(quotename(inserted.PrimaryKey4),'''') + isnull(quotename(inserted.PrimaryKey5),'''')' + Char(13) + Char(10)
		      + '	into @Keys (AuditHeaderID, PrimaryKey) '  + Char(13) + Char(10)
		      + '   SELECT ' 
		      
		      -- StrictUserOption
		      + CASE @StrictUserContext
		          WHEN 0 -- allow DML setting of created/modified user and datetimes
		            THEN ' COALESCE( src.' + @CreatedColumnName + ', @AuditTime), COALESCE( src.' + @CreatedByColumnName + ', Suser_SName()),'
		          ELSE -- block DML setting of user context 
		             ' @AuditTime, Suser_SName(),'
		        END 
		      
		      + ' APP_NAME(), Host_Name(), ' 
          + '''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''', ''i'',' --no quotename here
          
          -- if @LogSQL is off then the @UserSQL variable has not been declared
          + CASE @LogSQL
              WHEN 1 THEN ' @UserSQL, '
              ELSE ' NULL, ' 
           END  
          + Char(13) + Char(10)  
          + '		' + @PKColumnNameListWithDateConvert + ',' + left('null,null,null,null,',5*(5-@PKColumnQty)) + Char(13) + Char(10) 
          + '        NULL,     -- Row Description (e.g. Order Number)' + Char(13) + Char(10)   
          + '        NULL,     -- Secondary Row Value (e.g. Order Number for an Order Detail Line)' + Char(13) + Char(10)
          + '        1' + Char(13) + Char(10)      -- the RowVersion should always be 1 initially.  The RowVersion adjustment bellow sets it to the correct value
          + '          FROM  inserted as src' + Char(13) + Char(10)
          + '          WHERE  src.['+ c.name + '] is not null' + Char(13) + Char(10)+ Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.column_id = 1
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

--deal with RowVersion
	select @SQL = @SQL 
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
       + '	--calculate next row version' + Char(13) + Char(10)
       + '	;With NextRowVersions' + Char(13) + Char(10)
       + '	as' + Char(13) + Char(10)
       + '	(Select Keys.PrimaryKey, max(AH.[RowVersion]) + 1 as NextRowVersion' + Char(13) + Char(10)
       + '	From	' + quotename(@AuditSchema) + '.AuditHeader AH' + Char(13) + Char(10)
       + '	inner join @Keys as Keys' + Char(13) + Char(10)
       + '		on		quotename(AH.PrimaryKey) + isnull(quotename(AH.PrimaryKey2),'''') + isnull(quotename(AH.PrimaryKey3),'''') + isnull(quotename(AH.PrimaryKey4),'''') + isnull(quotename(AH.PrimaryKey5),'''') = Keys.PrimaryKey' + Char(13) + Char(10)--no quotename here
       + '		and		AH.TableName = ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '''' + Char(13) + Char(10)--no quotename here
       + '	group by Keys.PrimaryKey' + Char(13) + Char(10)
       + '	having count(*) > 1' + Char(13) + Char(10)
       + '	)' + Char(13) + Char(10)
       + '   UPDATE Keys' + Char(13) + Char(10)
       + '     SET  Keys.[NextRowVersion] = NRV.NextRowVersion' + Char(13) + Char(10)
       + '     FROM @Keys as Keys' + Char(13) + Char(10)
       + '     INNER JOIN	NextRowVersions NRV' + Char(13) + Char(10)
       + '		ON		Keys.PrimaryKey = NRV.PrimaryKey;' + Char(13) + Char(10)

	--fix the RowVersion in the Audit table to match the actual data table on re-insertion
	select @SQL = @SQL 
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
	   + ' -- fix the RowVersion in the Audit table' + Char(13) + Char(10)
       + '   UPDATE AH' + Char(13) + Char(10)
       + '     SET AH.[RowVersion] = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@AuditSchema) + '.AuditHeader AH with (nolock)' + Char(13) + Char(10)
       + '     INNER JOIN	@Keys as Keys' + Char(13) + Char(10)
       + '     ON AH.AuditHeaderID =  Keys.AuditHeaderID' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

--added RowVersion increment fix to continue to increment the RowVersion
--when a particular PK row is deleted then re-inserted
	IF @StrictUserContext = 1 AND @BaseTableDDL = 1
	select @SQL = @SQL 
	   + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
       + '   UPDATE src ' + Char(13) + Char(10)
       + '     SET ' + @CreatedColumnName + '  = @AuditTime, ' + Char(13) + Char(10)
       + '         ' + @CreatedByColumnName + '  = Suser_SName(), ' + Char(13) + Char(10)
       + '         ' + @ModifiedColumnName + ' = @AuditTime, ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = Suser_SName(), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]'
       +  Char(13) + Char(10) + Char(13) + Char(10)

	IF @StrictUserContext = 0 AND @BaseTableDDL = 1
	select @SQL = @SQL 	
       + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
       + '   UPDATE src' + Char(13) + Char(10)
       + '     SET ' + @CreatedColumnName + '  = COALESCE( inserted.' + @CreatedColumnName + ', @AuditTime), ' + Char(13) + Char(10)
       + '         ' + @CreatedByColumnName + '  = COALESCE( inserted.' + @CreatedByColumnName + ', Suser_SName()), ' + Char(13) + Char(10)
       + '         ' + @ModifiedColumnName + ' = COALESCE( inserted.' + @ModifiedColumnName + ',  inserted.' + @CreatedColumnName + ', @AuditTime), ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = COALESCE( inserted.' + @ModifiedByColumnName + ',  inserted.' + @CreatedByColumnName + ', Suser_SName()), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]'+ Char(13) + Char(10)
       + '       JOIN inserted'+ Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + Char(13) + Char(10)
       +  Char(13) + Char(10) 


----------------------------------------------------------------------------------
-- Insert AuditDetail Table
----------------------------------------------------------------------------------	  
----------------------------------------------------------------------------------
-- BEGIN FOR EACH COLUMN
----------------------------------------------------------------------------------	  
IF @LogInsert = 2 -- log data to the AuditDetail table
begin
	select @SQL = @SQL 
       + '   INSERT ' + quotename(@AuditSchema) + '.AuditDetail (AuditHeaderID, ColumnName, NewValue)' + Char(13) + Char(10)
--start of unpivot query
       + '   	SELECT AuditHeaderID, ''['' + AA_ColumnName + '']'', AA_NewValue' + Char(13) + Char(10)
       + '   FROM ' + Char(13) + Char(10)
       + '      (SELECT Keys.AuditHeaderID as AuditHeaderID' + Char(13) + Char(10)

--add columns to unpivot query       
 	select @SQL = @SQL  
       + '	,convert(varchar(50),inserted.[' + c.name + '],' + @DateStyle + ') as [' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      
       
 --data source for unpivot query       
	select @SQL = @SQL  
       + '	  FROM  inserted' + Char(13) + Char(10)
       + '	  JOIN	 @Keys as Keys' + Char(13) + Char(10)
       + '		ON	 ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' = Keys.PrimaryKey' + Char(13) + Char(10)
       + ') as SourceData' + Char(13) + Char(10)
       + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_NewValue FOR AA_ColumnName IN (' + Char(13) + Char(10)

--add filter to unpivot query       
 	select @SQL = @SQL  
       + case when c.column_id > 1 then ',' else '' end + quotename(c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      )' + Char(13) + Char(10)
       + ')AS UNPVT' + Char(13) + Char(10)
       + '	  WHERE  AA_NewValue is not null;' + Char(13) + Char(10) + Char(13) + Char(10)

end --@LogInsert = 2
----------------------------------------------------------------------------------
-- END FOR EACH COLUMN
----------------------------------------------------------------------------------	  

	select @SQL = @SQL 
       + '  set context_info 0x0;' + Char(13) + Char(10)

       + 'IF @DebugFlag = 1 PRINT ''Ending Insert trigger normally: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
       + ' End Try ' + Char(13) + Char(10)
       + ' Begin Catch ' + Char(13) + Char(10)
       + '   DECLARE @ErrorMessage NVARCHAR(4000), @ErrorSeverity INT, @ErrorState INT, @ErrorLine INT;' + Char(13) + Char(10) 

       + '   SET @ErrorMessage = ERROR_MESSAGE();  ' + Char(13) + Char(10)
       + '   SET @ErrorSeverity = ERROR_SEVERITY(); ' + Char(13) + Char(10) 
       + '   SET @ErrorState = ERROR_STATE();  ' + Char(13) + Char(10)
       + '   SET @ErrorLine = ERROR_LINE();  ' + Char(13) + Char(10)
       + '	 SET context_info 0x0;' + Char(13) + Char(10)
       + '   RAISERROR(@ErrorMessage,@ErrorSeverity,@ErrorState)' + case when @WithLogFlag = 1 then ' with log;' else ';' end + Char(13) + Char(10) 
       + '   PRINT ''Error Line: '' + cast(@ErrorLine as varchar);' + Char(13) + Char(10)
       + ' End Catch '

EXEC (@SQL)

SET @SQL = quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert')

EXEC sp_settriggerorder 
  @triggername= @SQL, 
  @order='First', 
  @stmttype = 'INSERT';

END --if @LogInsert > 0

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- build update trigger 
IF NOT (@LogUpdate = 0 and @BaseTableDDL = 0)
BEGIN
print '	Creating Update trigger'

SET @SQL = 'CREATE TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update') + ' ON ' + quotename(@SchemaName) + '.' + quotename(@TableName) + Char(13) + Char(10)
       + ' AFTER Update' + Char(13) + Char(10) + ' NOT FOR REPLICATION AS' + Char(13) + Char(10)
       + ' SET NoCount On ' + Char(13) + Char(10) + Char(13) + Char(10)
       
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10) + Char(13) + Char(10)
       
       + ' -- Options: ' + Char(13) + Char(10)
       + ' --   StrictUserContext : ' + CAST(@StrictUserContext as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogSQL            : ' + CAST(@LogSQL as CHAR(1)) + Char(13) + Char(10)
       + ' --   BaseTableDDL      : ' + CAST(@BaseTableDDL as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogInsert         : ' + CAST(@LogInsert as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogUpdate         : ' + CAST(@LogUpdate as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogDelete         : ' + CAST(@LogDelete as CHAR(1)) + Char(13) + Char(10) + Char(13) + Char(10)
       + ' --   ColumnNames       : ' + CAST(@ColumnNames as VARCHAR(1024)) + Char(13) + Char(10) + Char(13) + Char(10)
       
SET @SQL = @SQL 
    + 'declare  @DebugFlag BIT,' + Char(13) + Char(10)
    + '  @NestLevel TINYINT' + Char(13) + Char(10)

	+ 'Select @DebugFlag = SettingValue from ' + quotename(@AuditSchema) + '.[AuditSettings] where SettingName = ''Audit Trigger Debug Flag''' + Char(13) + Char(10)
	+ 'Select @NestLevel = TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update') + '''), ''AFTER'', ''DML'')' + Char(13) + Char(10) + Char(13) + Char(10)
    + 'IF @DebugFlag = 1 PRINT ''Firing Update trigger: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

	+ 'declare @ContextInfo varbinary(128)' + Char(13) + Char(10)
	+ 'select @ContextInfo = context_info from master.dbo.sysprocesses where spid=@@SPID;' + Char(13) + Char(10) + Char(13) + Char(10)

	+ '--prevent update trigger from firing when insert trigger is updating DDL columns' + Char(13) + Char(10)
	+ 'IF @ContextInfo = 0x1' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''   Update trigger initiated by the Insert trigger. Exiting Update trigger immediately...''' + Char(13) + Char(10)
    + ' 	   return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)

    + ' -- prevent recursive runs of this trigger' + Char(13) + Char(10)
    + ' IF TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update')+ '''), ''AFTER'', ''DML'') > 1' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''   TRIGGER_NESTLEVEL > 1. Exiting trigger...''' + Char(13) + Char(10)
    + ' 	   return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)

    + '  --get the EnabledFlag setting from the AuditBaseTables table' + Char(13) + Char(10)
	+ 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ ' WHERE [SchemaName] = ''' + @SchemaName + ''''
	+ ' AND [TableName] = ''' + @TableName + ''''
	+ ' AND [EnabledFlag] = 1)' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''AutoAudit EnabledFlag set to "false" for this table in the AuditBaseTables table. Exiting trigger...''' + Char(13) + Char(10)
	+ ' 	return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)

      + 'DECLARE ' + Char(13) + Char(10)
       + '  @AuditTime DATETIME' + Char(13) + Char(10)
       
       -- keep the variable initialization separate for SQL Server 2005
       + 'SET @AuditTime = GetDate()' + Char(13) + Char(10) + Char(13) + Char(10)

       + '  Begin Try' + Char(13) + Char(10)
  
   	        /* -------------------------------------------------------------------------------
   	        -- enable this code to force a rollback of attempt to set user context when StrictUserContext is on
   	        IF @StrictUserContext = 1
              SELECT @SQL = @SQL
                   -- StrictUserContext so always set to system user function        
                 + '    SET @CreateUserName = SUser_SName()' + Char(13) + Char(10)
                 + '    SET @ModifyUserName = SUser_SName()' + Char(13) + Char(10) + Char(13) + Char(10)
                   -- StrictUserContext so updating audit column not permitted 
                 + '    IF @@NestLevel = 1 AND (UPDATE(' + @CreatedColumnName + ') OR UPDATE(' + @CreatedByColumnName + ') OR UPDATE(' + @ModifiedColumnName + ') OR UPDATE(' + @ModifiedByColumnName + ') OR UPDATE(' + @RowVersionColumnName + '))' + Char(13) + Char(10)
                 + '      BEGIN ' + Char(13) + Char(10)
                 + '        RAISERROR(''Update of ' + @CreatedColumnName + ', ' + @CreatedByColumnName + ', ' + @ModifiedColumnName + ', ' + @ModifiedByColumnName + ', or ' + @RowVersionColumnName + ' not permitted by AutoAudit when StrictUserContext is enabled.'', 16,1)' + Char(13) + Char(10)
                 + '        ROLLBACK' + Char(13) + Char(10)
                 + '      END ' + Char(13) + Char(10)   + Char(13) + Char(10)  
             */ -------------------------------------------------------------------------------
 
IF @LogUpdate = 0
	BEGIN
		If @BaseTableDDL = 1
			BEGIN
				--no Audit record created but still update the Modified, ModifiedBy and RowVersion columns
				IF @StrictUserContext = 1
				select @SQL = @SQL 
				   + ' -- Update the Created columns' + Char(13) + Char(10)
				   + '   UPDATE src' + Char(13) + Char(10)
				   + '     SET ' + @CreatedColumnName + '  = deleted.' + @CreatedColumnName + ', ' + Char(13) + Char(10)
				   + '         ' + @CreatedByColumnName + '  = deleted.' + @CreatedByColumnName + Char(13) + Char(10)
				   + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
				   + '       JOIN deleted'+ Char(13) + Char(10)
				   + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert  + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','deleted.[') + Char(13) + Char(10)
				   + '     where	isnull(src.' + @CreatedColumnName + ',''1/1/1'')  <> isnull(deleted.' + @CreatedColumnName + ',''1/1/1'')' + Char(13) + Char(10)
				   + '	     or		isnull(src.' + @CreatedByColumnName + ',''wasnull!'')  <> isnull(deleted.' + @CreatedByColumnName + ',''wasnull!'')' + Char(13) + Char(10)
				   + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

				   + ' -- Update the Modified and RowVersion columns' + Char(13) + Char(10)
				   + '   UPDATE src' + Char(13) + Char(10)
				   + '     SET ' + @ModifiedColumnName + ' = @AuditTime, ' + Char(13) + Char(10)
				   + '         ' + @ModifiedByColumnName + '  = Suser_SName(), ' + Char(13) + Char(10)
				   + '         ' + @RowVersionColumnName + ' = isnull(src.' + @RowVersionColumnName + ',0) + 1' + Char(13) + Char(10)
				   + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
				   + '       JOIN  inserted'  + Char(13) + Char(10)
				   + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + Char(13) + Char(10)
				   + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

				IF @StrictUserContext = 0 
				select @SQL = @SQL 
				   + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
				   + '   UPDATE src' + Char(13) + Char(10)
				   + '     SET ' + Char(13) + Char(10)
				   + '         ' + @ModifiedColumnName + ' = COALESCE( inserted.' + @ModifiedColumnName + ', @AuditTime), ' + Char(13) + Char(10)
				   + '         ' + @ModifiedByColumnName + '  = COALESCE( inserted.' + @ModifiedByColumnName + ', Suser_SName()), ' + Char(13) + Char(10)
				   + '         ' + @RowVersionColumnName + ' = isnull(src.' + @RowVersionColumnName + ',0) + 1' + Char(13) + Char(10)
				   + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
				   + '       JOIN inserted'+ Char(13) + Char(10)
				   + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + Char(13) + Char(10)
				   +  Char(13) + Char(10) 
			END
	END
ELSE --IF @LogUpdate = 0
BEGIN
   IF @LogSQL = 1 
     BEGIN  
     	  -- capture SQL Statement' + Char(13) + Char(10)
		select @SQL = @SQL
         + ' DECLARE @ExecStr varchar(50), @UserSQL nvarchar(max)' + Char(13) + Char(10)
         + ' DECLARE @inputbuffer TABLE' + Char(13) + Char(10) 
         + ' (EventType nvarchar(30), Parameters int, EventInfo nvarchar(max))' + Char(13) + Char(10)
         + ' SET @ExecStr = ''DBCC INPUTBUFFER(@@SPID) with no_infomsgs''' + Char(13) + Char(10)
         + ' INSERT INTO @inputbuffer' + Char(13) + Char(10) 
         + '   EXEC (@ExecStr)' + Char(13) + Char(10)
         + ' SELECT @UserSQL = EventInfo FROM @inputbuffer' + Char(13) + Char(10)
         + Char(13) + Char(10) 
     END   

--create a temp table for mapping keys
select @SQL = @SQL
		+ 'Declare @Keys Table (AuditHeaderID BIGINT, PrimaryKey VARCHAR(250), NextRowVersion int default(0))' + Char(13) + Char(10) 
        + 'Declare @AuditDetailUpdate Table (PrimaryKey VARCHAR(250), ColumnName sysname, OldValue varchar(50), NewValue varchar(50))' + Char(13) + Char(10)
        + 'Declare @CleanRows Table (AuditHeaderID bigint)' + Char(13) + Char(10)
        + 'Declare @PrimaryKeys Table (PrimaryKey VARCHAR(250))' + Char(13) + Char(10) + Char(13) + Char(10)

	select @SQL = @SQL
		+ '--BAIL OUT NOW IF NO ROWS HAVE BEEN UPDATED' + Char(13) + Char(10)
		+ 'If (Select count(*) from deleted) = 0 ' + Char(13) + Char(10)
		+ '   Begin' + Char(13) + Char(10)
        + '     IF @DebugFlag = 1 PRINT ''   No rows affected by update statement. Exiting trigger...''' + Char(13) + Char(10)
        + '     return --nothing has changed - bail out of trigger' + Char(13) + Char(10)
		+ '   End' + Char(13) + Char(10) + Char(13) + Char(10)

		+ '	--****************************************************** ' + Char(13) + Char(10)   
		+ '	--***START - THIS SECTION IS USED WHEN THE PK IS CHANGED ' + Char(13) + Char(10)   
		+ '	--****************************************************** ' + Char(13) + Char(10)   
		+ @PKColumnNameListIfUpdate + ' --check if the PK column has been updated' + Char(13) + Char(10)
		+ '		begin	--the primary key has been changed' + Char(13) + Char(10)
		+ '		If (Select count(*) from deleted) = 1 --check if more than one PK value has been updated' + Char(13) + Char(10)
		+ '			begin	--the primary key has been changed on a single row' + Char(13) + Char(10) + Char(13) + Char(10)

----------------------------------------------------------------------------------
-- BEGIN FOR EACH COLUMN
----------------------------------------------------------------------------------	  
       + '   INSERT @AuditDetailUpdate (PrimaryKey, ColumnName, OldValue, NewValue)' + Char(13) + Char(10)
 --start of unpivot query
      + '   	SELECT PrimaryKey, ''['' + substring(AA_dColumnName ,2,128) + '']'', AA_OldValue, AA_NewValue' + Char(13) + Char(10)
       + '   FROM ' + Char(13) + Char(10)
       + '      (SELECT ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' as PrimaryKey' + Char(13) + Char(10)
       
--add columns to unpivot query       
 	select @SQL = @SQL  
       + '	,isnull(convert(varchar(50),deleted.[' + c.name + '],' + @DateStyle + '),''<-null->'') as [d' + c.name + ']' + Char(13) + Char(10)
       + '	,isnull(convert(varchar(50),inserted.[' + c.name + '],' + @DateStyle + '),''<-null->'') as [i' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      
 
 --data source for unpivot query       
	select @SQL = @SQL  
       + '	  FROM  inserted' + Char(13) + Char(10)
       + '             CROSS JOIN deleted' + Char(13) + Char(10)
      + ') as SourceData' + Char(13) + Char(10)
     + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_OldValue FOR AA_dColumnName IN (' + Char(13) + Char(10)

--add columns to unpivot query for deleted data   
 	select @SQL = @SQL  
       + case when column_id > 1 then ',' else '' end + quotename('d' + c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      ))AS dUNPVT' + Char(13) + Char(10)

     + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_NewValue FOR AA_iColumnName IN (' + Char(13) + Char(10)

--add columns to unpivot query for inserted data   
 	select @SQL = @SQL  
       + case when column_id > 1 then ',' else '' end + quotename('i' + c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      ))AS iUNPVT' + Char(13) + Char(10)
      + '	  WHERE  substring(AA_dColumnName ,2,128) = substring(AA_iColumnName ,2,128)' + Char(13) + Char(10)
      + '	  AND ISNULL(AA_OldValue,''<-null->'') <> ISNULL(AA_NewValue,''<-null->'')' + Char(13) + Char(10)  + Char(13) + Char(10)

----------------------------------------------------------------------------------
-- END FOR EACH COLUMN
----------------------------------------------------------------------------------

-- Insert the AuditHeader row for PK changes
	select @SQL = @SQL  
         + '   INSERT @PrimaryKeys select distinct PrimaryKey from @AuditDetailUpdate '  + Char(13) + Char(10)  
         + '   INSERT ' + quotename(@AuditSchema) + '.AuditHeader (AuditDate, SysUser, Application, HostName, TableName, Operation, SQLStatement, '  + Char(13) + Char(10)
         + '   PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, RowDescription, SecondaryRow, [RowVersion]) '  + Char(13) + Char(10)  
		 + '   OUTPUT  inserted.AuditHeaderID, quotename(inserted.PrimaryKey) + isnull(quotename(inserted.PrimaryKey2),'''') + isnull(quotename(inserted.PrimaryKey3),'''') + isnull(quotename(inserted.PrimaryKey4),'''') + isnull(quotename(inserted.PrimaryKey5),''''), inserted.[RowVersion] into @Keys (AuditHeaderID, PrimaryKey, NextRowVersion)' + Char(13) + Char(10) 
         + '     SELECT '

         -- StrictUserOption
   	     + CASE 
   	         WHEN @StrictUserContext = 1 THEN ' @AuditTime, SUSER_SNAME(),'
   	         ELSE 'COALESCE( inserted.' + @ModifiedColumnName + ', @AuditTime), COALESCE( inserted.' + @ModifiedByColumnName + ', Suser_Sname()),'
           END

         + ' APP_NAME(), Host_Name(), ' 
         + '''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''', ''u'','  --no quotename here

         -- if @LogSQL is off then the @UserSQL variable has not been declared
         + CASE @LogSQL
             WHEN 1 THEN ' @UserSQL, '
             ELSE ' NULL, ' 
           END  
          + '		' + replace(@PKColumnNameListWithDateConvert,'src.[','inserted.[') + ',' + left('null,null,null,null,',5*(5-@PKColumnQty)) + Char(13) + Char(10) 
       + '        NULL,     -- Row Description (e.g. Order Number)' + Char(13) + Char(10)   
       + '        NULL,     -- Secondary Row Value (e.g. Order Number for an Order Detail Line)' + Char(13) + Char(10)
          + '1' + Char(13) + Char(10)
       + '          FROM  inserted' + Char(13) + Char(10)
       + '             CROSS JOIN deleted' + Char(13) + Char(10)     
       + '          WHERE ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' in (Select PrimaryKey from @PrimaryKeys)' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.column_id = 1


--deal with RowVersion
	select @SQL = @SQL 
       + '	--calculate next row version' + Char(13) + Char(10)
       + '	;With NextRowVersions' + Char(13) + Char(10)
       + '	as' + Char(13) + Char(10)
       + '	(Select Keys.PrimaryKey, max(AH.[RowVersion]) + 1 as NextRowVersion' + Char(13) + Char(10)
       + '	From	' + quotename(@AuditSchema) + '.AuditHeader AH' + Char(13) + Char(10)
       + '	inner join @Keys as Keys' + Char(13) + Char(10)
       + '		on		quotename(AH.PrimaryKey) + isnull(quotename(AH.PrimaryKey2),'''') + isnull(quotename(AH.PrimaryKey3),'''') + isnull(quotename(AH.PrimaryKey4),'''') + isnull(quotename(AH.PrimaryKey5),'''') = Keys.PrimaryKey' + Char(13) + Char(10)--no quotename here
       + '		and		AH.TableName = ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '''' + Char(13) + Char(10)--no quotename here
       + '	group by Keys.PrimaryKey' + Char(13) + Char(10)
       + '	having count(*) > 1' + Char(13) + Char(10)
       + '	)' + Char(13) + Char(10)
       + '   UPDATE Keys' + Char(13) + Char(10)
       + '     SET  Keys.[NextRowVersion] = NRV.NextRowVersion' + Char(13) + Char(10)
       + '     FROM @Keys as Keys' + Char(13) + Char(10)
       + '     INNER JOIN	NextRowVersions NRV' + Char(13) + Char(10)
       + '		ON		Keys.PrimaryKey = NRV.PrimaryKey;' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	--fix the RowVersion in the Audit table to match the actual data table on re-insertion
	select @SQL = @SQL 
	   + ' -- fix the RowVersion in the Audit table' + Char(13) + Char(10)
       + '   UPDATE AH' + Char(13) + Char(10)
       + '     SET AH.[RowVersion] = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@AuditSchema) + '.AuditHeader AH with (nolock) ' + Char(13) + Char(10)
       + '     INNER JOIN	@Keys as Keys' + Char(13) + Char(10)
       + '     ON AH.AuditHeaderID =  Keys.AuditHeaderID' + Char(13) + Char(10)
       + '     WHERE Keys.[NextRowVersion] <> 1' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

--added RowVersion increment fix to continue to increment the RowVersion
--when a particular PK row is deleted then re-inserted
	IF @StrictUserContext = 1 AND @BaseTableDDL = 1
	select @SQL = @SQL 
	     + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
       + '   UPDATE src ' + Char(13) + Char(10)
       + '     SET ' + @CreatedColumnName + '  = deleted.' + @CreatedColumnName + ', ' + Char(13) + Char(10)
       + '         ' + @CreatedByColumnName + '  = deleted.' + @CreatedByColumnName + ', ' + Char(13) + Char(10)
       + '         ' + @ModifiedColumnName + ' = @AuditTime, ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = Suser_SName(), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]'
       + '     CROSS JOIN  deleted'  + Char(13) + Char(10)--OK, there's only one row for PK changes
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	IF @StrictUserContext = 0 AND @BaseTableDDL = 1
	select @SQL = @SQL 
	
       + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
       + '   UPDATE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + Char(13) + Char(10)
       + '     SET ' + Char(13) + Char(10)
       + '         ' + @ModifiedColumnName + ' = COALESCE( inserted.' + @ModifiedColumnName + ', @AuditTime), ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = COALESCE( inserted.' + @ModifiedByColumnName + ', Suser_SName()), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src  with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]' + Char(13) + Char(10)
       + '       JOIN inserted'+ Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	SELECT @SQL = @SQL 
        + '		end	  --the primary key has been changed on a single row'+ Char(13) + Char(10) 
		+ '		end	--the primary key has been changed' + Char(13) + Char(10)

		+ '	--****************************************************** ' + Char(13) + Char(10)   
		+ '	--***END - THIS SECTION IS USED WHEN THE PK IS CHANGED ' + Char(13) + Char(10)   
		+ '	--****************************************************** ' + Char(13) + Char(10)   
        + Char(13) + Char(10) + Char(13) + Char(10)


		+ '	--********************************************************** ' + Char(13) + Char(10)   
		+ '	--***START - THIS SECTION IS USED WHEN THE PK IS NOT CHANGED ' + Char(13) + Char(10)   
		+ '	--********************************************************** ' + Char(13) + Char(10)   

		+ 'else' + Char(13) + Char(10)
		+ '		begin	--the primary key has NOT been changed' + Char(13) + Char(10)


----------------------------------------------------------------------------------
-- BEGIN FOR EACH COLUMN
----------------------------------------------------------------------------------	  
	select @SQL = @SQL  
       + '   INSERT @AuditDetailUpdate (PrimaryKey, ColumnName, OldValue, NewValue)' + Char(13) + Char(10)
 --start of unpivot query
      + '   	SELECT PrimaryKey, ''['' + substring(AA_dColumnName ,2,128) + '']'', AA_OldValue, AA_NewValue' + Char(13) + Char(10)
       + '   FROM ' + Char(13) + Char(10)
       + '      (SELECT ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' as PrimaryKey' + Char(13) + Char(10)
       
--add columns to unpivot query       
 	select @SQL = @SQL  
       + '	,isnull(convert(varchar(50),deleted.[' + c.name + '],' + @DateStyle + '),''<-null->'') as [d' + c.name + ']' + Char(13) + Char(10)
       + '	,isnull(convert(varchar(50),inserted.[' + c.name + '],' + @DateStyle + '),''<-null->'') as [i' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      
 
      
 --data source for unpivot query       
	select @SQL = @SQL  
       + '          FROM  inserted' + Char(13) + Char(10)
       + '             JOIN deleted' + Char(13) + Char(10)
       + '               ON  ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','deleted.[') + Char(13) + Char(10)
       + ') as SourceData' + Char(13) + Char(10)
 
     + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_OldValue FOR AA_dColumnName IN (' + Char(13) + Char(10)

--add columns to unpivot query for deleted data   
 	select @SQL = @SQL  
       + case when c.column_id > 1 then ',' else '' end + quotename('d' + c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      ))AS dUNPVT' + Char(13) + Char(10)

     + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_NewValue FOR AA_iColumnName IN (' + Char(13) + Char(10)

--add columns to unpivot query for inserted data   
 	select @SQL = @SQL  
       + case when c.column_id > 1 then ',' else '' end + quotename('i' + c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      ))AS iUNPVT' + Char(13) + Char(10)
      + '	  WHERE  substring(AA_dColumnName ,2,128) = substring(AA_iColumnName ,2,128)' + Char(13) + Char(10)
      + '	  AND ISNULL(AA_OldValue,''<-null->'') <> ISNULL(AA_NewValue,''<-null->'')' + Char(13) + Char(10) + Char(13) + Char(10)
      + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

----------------------------------------------------------------------------------
-- END FOR EACH COLUMN
----------------------------------------------------------------------------------	  

--  Insert the AuditHeader row for NO PK changes
	select @SQL = @SQL  
         + '   INSERT @PrimaryKeys select distinct PrimaryKey from @AuditDetailUpdate '  + Char(13) + Char(10)  
         + '   INSERT ' + quotename(@AuditSchema) + '.AuditHeader (AuditDate, SysUser, Application, HostName, TableName, Operation, SQLStatement, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, RowDescription, SecondaryRow, [RowVersion]) '  + Char(13) + Char(10)  
		 + '   OUTPUT  inserted.AuditHeaderID, quotename(inserted.PrimaryKey) + isnull(quotename(inserted.PrimaryKey2),'''') + isnull(quotename(inserted.PrimaryKey3),'''') + isnull(quotename(inserted.PrimaryKey4),'''') + isnull(quotename(inserted.PrimaryKey5),''''), inserted.[RowVersion] into @Keys (AuditHeaderID, PrimaryKey, NextRowVersion)' + Char(13) + Char(10) 
         + '     SELECT '

         -- StrictUserOption
   	     + CASE 
   	         WHEN @StrictUserContext = 1 THEN ' @AuditTime, SUSER_SNAME(),'
   	         ELSE 'COALESCE( inserted.' + @ModifiedColumnName + ', @AuditTime), COALESCE( inserted.' + @ModifiedByColumnName + ', Suser_Sname()),'
           END

         + ' APP_NAME(), Host_Name(), ' 
         + '''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''', ''u'','  --no quotename here

         -- if @LogSQL is off then the @UserSQL variable has not been declared
         + CASE @LogSQL
             WHEN 1 THEN ' @UserSQL, '
             ELSE ' NULL, ' 
           END  
          + '  ' + replace(@PKColumnNameListWithDateConvert,'src.[','inserted.[') + ',' + left('null,null,null,null,',5*(5-@PKColumnQty)) + Char(13) + Char(10) 
       + '        NULL,     -- Row Description (e.g. Order Number)' + Char(13) + Char(10)   
       + '        NULL,     -- Secondary Row Value (e.g. Order Number for an Order Detail Line)' + Char(13) + Char(10)
          + case @BaseTableDDL 
				when 1 then ' deleted.' + @RowVersionColumnName + ' + 1' + Char(13) + Char(10)
				ELSE 		'1' + Char(13) + Char(10)
			END
       + '          FROM  inserted' + Char(13) + Char(10)
       + '             JOIN deleted' + Char(13) + Char(10)
       + '               ON ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','deleted.[') + Char(13) + Char(10)       
       + '          WHERE ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + ' in (Select PrimaryKey from @PrimaryKeys)' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.column_id = 1

--deal with RowVersion
	select @SQL = @SQL 
       + case when @BaseTableDDL = 0 or @LogInsert = 0 then --added @LogInsert = 0 2013-01-29
        '	--calculate next row version' + Char(13) + Char(10)
       + '	;With NextRowVersions' + Char(13) + Char(10)
       + '	as' + Char(13) + Char(10)
       + '	(Select Keys.PrimaryKey, max(AH.[RowVersion]) + 1 as NextRowVersion' + Char(13) + Char(10)
       + '	From	' + quotename(@AuditSchema) + '.AuditHeader AH' + Char(13) + Char(10)
       + '	inner join @Keys as Keys' + Char(13) + Char(10)
       + '		on		quotename(AH.PrimaryKey) + isnull(quotename(AH.PrimaryKey2),'''') + isnull(quotename(AH.PrimaryKey3),'''') + isnull(quotename(AH.PrimaryKey4),'''') + isnull(quotename(AH.PrimaryKey5),'''') = Keys.PrimaryKey' + Char(13) + Char(10)--no quotename here
       + '		and		AH.TableName = ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '''' + Char(13) + Char(10)--no quotename here
       + '	group by Keys.PrimaryKey' + Char(13) + Char(10)
       + '	having count(*) > 1' + Char(13) + Char(10)
       + '	)' + Char(13) + Char(10)
       + '   UPDATE Keys' + Char(13) + Char(10)
       + '     SET  Keys.[NextRowVersion] = NRV.NextRowVersion' + Char(13) + Char(10)
       + '     FROM @Keys as Keys' + Char(13) + Char(10)
       + '     INNER JOIN	NextRowVersions NRV' + Char(13) + Char(10)
       + '		ON		Keys.PrimaryKey = NRV.PrimaryKey;' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
		else '' + Char(13) + Char(10)
		END

	--fix the RowVersion in the Audit table to match the actual data table on re-insertion
	select @SQL = @SQL 
	   + ' -- fix the RowVersion in the Audit table' + Char(13) + Char(10)
       + '   UPDATE AH' + Char(13) + Char(10)
       + '     SET AH.[RowVersion] = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@AuditSchema) + '.AuditHeader AH with (nolock)' + Char(13) + Char(10)
       + '     INNER JOIN	@Keys as Keys' + Char(13) + Char(10)
       + '     ON AH.AuditHeaderID =  Keys.AuditHeaderID' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

--added RowVersion increment fix to continue to increment the RowVersion
--when a particular PK row is deleted then re-inserted
	IF @StrictUserContext = 1 AND @BaseTableDDL = 1
	select @SQL = @SQL 
	   + ' -- Update the Created columns' + Char(13) + Char(10)
       + '   UPDATE src ' + Char(13) + Char(10)
       + '     SET ' + @CreatedColumnName + '  = deleted.' + @CreatedColumnName + ', ' + Char(13) + Char(10)
       + '         ' + @CreatedByColumnName + '  = deleted.' + @CreatedByColumnName + ' ' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN deleted'+ Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','deleted.[') + Char(13) + Char(10)
       + '     where	isnull(src.' + @CreatedColumnName + ',''1/1/1'')  <> isnull(deleted.' + @CreatedColumnName + ',''1/1/1'')' + Char(13) + Char(10)
       + '	     or		isnull(src.' + @CreatedByColumnName + ',''wasnull!'')  <> isnull(deleted.' + @CreatedByColumnName + ',''wasnull!'')' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	   + ' -- Update the Modified and RowVersion columns' + Char(13) + Char(10)
       + '   UPDATE src ' + Char(13) + Char(10)
       + '     SET ' + @ModifiedColumnName + ' = @AuditTime, ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = Suser_SName(), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]'
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	IF @StrictUserContext = 0 AND @BaseTableDDL = 1
	select @SQL = @SQL 
       + ' -- Update the Created and Modified columns' + Char(13) + Char(10)
       + '   UPDATE src '  + Char(13) + Char(10)
       + '     SET ' + Char(13) + Char(10)
       + '         ' + @ModifiedColumnName + ' = COALESCE( inserted.' + @ModifiedColumnName + ', @AuditTime), ' + Char(13) + Char(10)
       + '         ' + @ModifiedByColumnName + '  = COALESCE( inserted.' + @ModifiedByColumnName + ', Suser_SName()), ' + Char(13) + Char(10)
       + '         ' + @RowVersionColumnName + ' = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' as src with (nolock) ' + Char(13) + Char(10)
       + '       JOIN  @Keys as Keys'  + Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' =  Keys.[PrimaryKey]'
       + '       JOIN inserted'+ Char(13) + Char(10)
       + '         ON ' + @PKColumnNameConcatenationWithQuotenameAndDateConvert + ' = ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','inserted.[') + Char(13) + Char(10)
       +  Char(13) + Char(10) 
	SELECT @SQL = @SQL 
	   + '		end	--the primary key has NOT been changed' + Char(13) + Char(10)

        +  Char(13) + Char(10) + Char(13) + Char(10)
		+ '	--********************************************************** ' + Char(13) + Char(10)   
		+ '	--***END - THIS SECTION IS USED WHEN THE PK IS NOT CHANGED ' + Char(13) + Char(10)   
		+ '	--********************************************************** ' + Char(13) + Char(10)   
  
        + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

--insert AuditDetail table
 IF @LogUpdate = 2 -- log data to the AuditDetail table
	select @SQL = @SQL + 
       + '   INSERT ' + quotename(@AuditSchema) + '.AuditDetail (AuditHeaderID, ColumnName, OldValue, NewValue)' + Char(13) + Char(10)
       + '   Select	Keys.AuditHeaderID, ADU.ColumnName, ADU.OldValue, ADU.NewValue ' + Char(13) + Char(10) 
       + '   from @AuditDetailUpdate ADU' + Char(13) + Char(10) 
       + '   INNER JOIN @Keys as Keys' + Char(13) + Char(10)
       + '		ON	ADU.PrimaryKey = Keys.PrimaryKey;' + Char(13) + Char(10) + Char(13) + Char(10) 

END -- IF @LogUpdate = 0 (ELSE)

	select @SQL = @SQL + 
       + 'IF @DebugFlag = 1 PRINT ''Ending Update trigger normally: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

        + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' End Try ' + Char(13) + Char(10)
       + ' Begin Catch ' + Char(13) + Char(10)
       + '   DECLARE @ErrorMessage NVARCHAR(4000), @ErrorSeverity INT, @ErrorState INT, @ErrorLine INT;' + Char(13) + Char(10) 

       + '   SET @ErrorMessage = ERROR_MESSAGE();  ' + Char(13) + Char(10)
       + '   SET @ErrorSeverity = ERROR_SEVERITY(); ' + Char(13) + Char(10) 
       + '   SET @ErrorState = ERROR_STATE();  ' + Char(13) + Char(10)
       + '   SET @ErrorLine = ERROR_LINE();  ' + Char(13) + Char(10)
       + '   RAISERROR(@ErrorMessage,@ErrorSeverity,@ErrorState)' + case when @WithLogFlag = 1 then ' with log;' else ';' end + Char(13) + Char(10) 
       + '   PRINT ''Error Line: '' + cast(@ErrorLine as varchar);' + Char(13) + Char(10)

       + ' End Catch ' 

EXEC (@SQL)

SET @SQL = quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update')

EXEC sp_settriggerorder 
  @triggername= @SQL, 
  @order='Last', 
  @stmttype = 'UPDATE';

END --IF NOT (@LogUpdate = 0 @BaseTableDDL = 0)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- build delete trigger 
If @LogDelete > 0
BEGIN
print '	Creating Delete trigger'

SET @SQL = 'CREATE TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete') + ' ON ' + quotename(@SchemaName) + '.' + quotename(@TableName) + Char(13) + Char(10)
       + ' AFTER Delete' + Char(13) + Char(10) + ' NOT FOR REPLICATION AS' + Char(13) + Char(10)
       + ' SET NoCount On ' + Char(13) + Char(10) + Char(13) + Char(10)
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' -- Options: ' + Char(13) + Char(10)
       + ' --   StrictUserContext : ' + CAST(@StrictUserContext as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogSQL            : ' + CAST(@LogSQL as CHAR(1)) + Char(13) + Char(10)
       + ' --   BaseTableDDL      : ' + CAST(@BaseTableDDL as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogInsert         : ' + CAST(@LogInsert as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogUpdate         : ' + CAST(@LogUpdate as CHAR(1)) + Char(13) + Char(10)
       + ' --   LogDelete         : ' + CAST(@LogDelete as CHAR(1)) + Char(13) + Char(10) 
       + ' --   ColumnNames       : ' + CAST(@ColumnNames as VARCHAR(1024)) + Char(13) + Char(10) + Char(13) + Char(10)
      
SELECT @SQL = @SQL 
    + 'declare  @DebugFlag BIT,' + Char(13) + Char(10)
    + '  @NestLevel TINYINT' + Char(13) + Char(10)

	+ 'Select @DebugFlag = SettingValue from ' + quotename(@AuditSchema) + '.[AuditSettings] where SettingName = ''Audit Trigger Debug Flag''' + Char(13) + Char(10)
	+ 'Select @NestLevel = TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete') + '''), ''AFTER'', ''DML'')' + Char(13) + Char(10) + Char(13) + Char(10)
    + 'IF @DebugFlag = 1 PRINT ''Firing Delete trigger: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

    + ' -- prevent recursive runs of this trigger' + Char(13) + Char(10)
    + ' IF TRIGGER_NESTLEVEL(OBJECT_ID(''' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete')+ '''), ''AFTER'', ''DML'') > 1' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''   TRIGGER_NESTLEVEL > 1. Exiting trigger...''' + Char(13) + Char(10)
    + ' 	   return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)
       
	+ '--get the EnabledFlag setting from the AuditBaseTables table' + Char(13) + Char(10)
	+ 'IF NOT EXISTS (SELECT 1 FROM ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ ' WHERE [SchemaName] = ''' + @SchemaName + ''''
	+ ' AND [TableName] = ''' + @TableName + ''''
	+ ' AND [EnabledFlag] = 1)' + Char(13) + Char(10)
    + '   BEGIN' + Char(13) + Char(10)
    + '     IF @DebugFlag = 1 PRINT ''AutoAudit EnabledFlag set to "false" for this table in the AuditBaseTables table. Exiting trigger...''' + Char(13) + Char(10)
	+ ' 	return' + Char(13) + Char(10)
    + '   END' + Char(13) + Char(10) + Char(13) + Char(10)

       + 'DECLARE @AuditTime DATETIME' + Char(13) + Char(10)
       + 'SET @AuditTime = GetDate()' + Char(13) + Char(10) + Char(13) + Char(10)
       
       + ' Begin Try ' + Char(13) + Char(10)
       
   IF @LogSQL = 1 
     BEGIN  
     	 select @SQL = @SQL
         + ' -- capture SQL Statement' + Char(13) + Char(10)
         + ' DECLARE @ExecStr varchar(50), @UserSQL nvarchar(max)' + Char(13) + Char(10)
         + ' DECLARE  @inputbuffer TABLE' + Char(13) + Char(10) 
         + ' (EventType nvarchar(30), Parameters int, EventInfo nvarchar(max))' + Char(13) + Char(10)
         + ' SET @ExecStr = ''DBCC INPUTBUFFER(@@SPID) with no_infomsgs''' + Char(13) + Char(10)
         + ' INSERT INTO @inputbuffer' + Char(13) + Char(10) 
         + '   EXEC (@ExecStr)' + Char(13) + Char(10)
         + ' SELECT @UserSQL = EventInfo FROM @inputbuffer' + Char(13) + Char(10)
         + Char(13) + Char(10) 
     END   

--create a temp table for mapping keys
select @SQL = @SQL
		+ 'Declare @Keys Table (AuditHeaderID BIGINT, PrimaryKey VARCHAR(250), NextRowVersion int default(0))' + Char(13) + Char(10) 

-- Insert the AuditHeader row
	select @SQL = @SQL
          + Char(13) + Char(10)
		      + '   INSERT ' + quotename(@AuditSchema) + '.AuditHeader (AuditDate, SysUser, Application, HostName, TableName, Operation, SQLStatement, PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, RowDescription, SecondaryRow, [RowVersion])' + Char(13) + Char(10)
		      + '   OUTPUT  inserted.AuditHeaderID,  quotename(inserted.PrimaryKey) + isnull(quotename(inserted.PrimaryKey2),'''') + isnull(quotename(inserted.PrimaryKey3),'''') + isnull(quotename(inserted.PrimaryKey4),'''') + isnull(quotename(inserted.PrimaryKey5),'''') into @Keys (AuditHeaderID,PrimaryKey) '  + Char(13) + Char(10)
		      + '   SELECT ' 
		      
		      -- StrictUserOption
		      + CASE @StrictUserContext
		          WHEN 0 -- allow DML setting of created/modified user and datetimes
		            THEN ' COALESCE( src.' + @ModifiedColumnName + ', @AuditTime), COALESCE( src.' + @ModifiedByColumnName + ', Suser_SName()),'
		          ELSE -- block DML setting of user context 
		             ' @AuditTime, Suser_SName(),'
		        END 
		      
		      + ' APP_NAME(), Host_Name(), ' 
          + '''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''', ''d'','  --no quotename here
          
          -- if @LogSQL is off then the @UserSQL variable has not been declared
          + CASE @LogSQL
              WHEN 1 THEN ' @UserSQL, '
              ELSE ' NULL, ' 
           END  
          + Char(13) + Char(10)  
          
          + '  ' + @PKColumnNameListWithDateConvert + ',' + left('null,null,null,null,',5*(5-@PKColumnQty)) + Char(13) + Char(10) 
          + '        NULL,     -- Row Description (e.g. Order Number)' + Char(13) + Char(10)   
          + '        NULL,     -- Secondary Row Value (e.g. Order Number for an Order Detail Line)' + Char(13) + Char(10)
          + '0'
          + '          FROM  deleted as src' + Char(13) + Char(10)
          + '          WHERE  src.['+ c.name + '] is not null' + Char(13) + Char(10)+ Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.column_id = 1

--deal with RowVersion
	select @SQL = @SQL 
 	   + '-----' + Char(13) + Char(10) + Char(13) + Char(10)
       + '	--calculate next row version' + Char(13) + Char(10)
       + '	;With NextRowVersions' + Char(13) + Char(10)
       + '	as' + Char(13) + Char(10)
       + '	(Select Keys.PrimaryKey, max(AH.[RowVersion]) + 1 as NextRowVersion' + Char(13) + Char(10)
       + '	From	' + quotename(@AuditSchema) + '.AuditHeader AH' + Char(13) + Char(10)
       + '	inner join @Keys as Keys' + Char(13) + Char(10)
       + '		on		quotename(AH.PrimaryKey) + isnull(quotename(AH.PrimaryKey2),'''') + isnull(quotename(AH.PrimaryKey3),'''') + isnull(quotename(AH.PrimaryKey4),'''') + isnull(quotename(AH.PrimaryKey5),'''') = Keys.PrimaryKey' + Char(13) + Char(10)--no quotename here
       + '		and		AH.TableName = ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '''' + Char(13) + Char(10)--no quotename here
       + '	group by Keys.PrimaryKey' + Char(13) + Char(10)
       + '	)' + Char(13) + Char(10)
       + '   UPDATE Keys' + Char(13) + Char(10)
       + '     SET  Keys.[NextRowVersion] = NRV.NextRowVersion' + Char(13) + Char(10)
       + '     FROM @Keys as Keys' + Char(13) + Char(10)
       + '     INNER JOIN	NextRowVersions NRV' + Char(13) + Char(10)
       + '		ON		Keys.PrimaryKey = NRV.PrimaryKey;' + Char(13) + Char(10) 
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

	--fix the RowVersion in the Audit table to match the actual data table on re-insertion
	select @SQL = @SQL 
	   + ' -- fix the RowVersion in the Audit table' + Char(13) + Char(10)
       + '   UPDATE AH' + Char(13) + Char(10)
       + '     SET AH.[RowVersion] = Keys.[NextRowVersion]' + Char(13) + Char(10)
       + '     FROM ' + quotename(@AuditSchema) + '.AuditHeader AH with (nolock)' + Char(13) + Char(10)
       + '     INNER JOIN	@Keys as Keys' + Char(13) + Char(10)
       + '     ON AH.AuditHeaderID =  Keys.AuditHeaderID' + Char(13) + Char(10)
       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

If @LogDelete = 2
BEGIN
----------------------------------------------------------------------------------
-- Insert AuditDetail Table
----------------------------------------------------------------------------------	  
----------------------------------------------------------------------------------
-- BEGIN FOR EACH COLUMN
----------------------------------------------------------------------------------	  
	select @SQL = @SQL  
       + '   INSERT ' + quotename(@AuditSchema) + '.AuditDetail (AuditHeaderID, ColumnName, OldValue)' + Char(13) + Char(10)
--start of unpivot query
       + '   	SELECT AuditHeaderID, ''['' + AA_ColumnName + '']'', AA_OldValue' + Char(13) + Char(10)
       + '   FROM ' + Char(13) + Char(10)
       + '      (SELECT Keys.AuditHeaderID as AuditHeaderID' + Char(13) + Char(10)

--add columns to unpivot query       
 	select @SQL = @SQL  
       + '	,convert(varchar(50),deleted.[' + c.name + '],' + @DateStyle + ') as [' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      
       
 --data source for unpivot query       
	select @SQL = @SQL  
       + '	  FROM  deleted' + Char(13) + Char(10)
       + '	  JOIN	 @Keys as Keys' + Char(13) + Char(10)
       + '		ON	 ' + replace(@PKColumnNameConcatenationWithQuotenameAndDateConvert,'src.[','deleted.[') + ' = Keys.PrimaryKey' + Char(13) + Char(10)
       + ') as SourceData' + Char(13) + Char(10)
       + 'UNPIVOT' + Char(13) + Char(10)
       + '   (AA_OldValue FOR AA_ColumnName IN (' + Char(13) + Char(10)

--add filter to unpivot query       
 	select @SQL = @SQL  
       + case when c.column_id > 1 then ',' else '' end + quotename(c.name) + Char(13) + Char(10)
	  from sys.tables as t
		  join sys.columns as c
		    on t.object_id = c.object_id
		  join sys.schemas as s
		    on s.schema_id = t.schema_id
		  join sys.types as ty
		    on ty.user_type_id = c.user_type_id
        where t.name = @TableName AND s.name = @SchemaName 
           AND c.is_computed = 0
           AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
           AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id      

  	select @SQL = @SQL  
      + '      )' + Char(13) + Char(10)
       + ')AS UNPVT' + Char(13) + Char(10)
       + '	  WHERE  AA_OldValue is not null' + Char(13) + Char(10) + Char(13) + Char(10)

----------------------------------------------------------------------------------
-- END FOR EACH COLUMN
----------------------------------------------------------------------------------	  
END --If @LogDelete = 2

	select @SQL = @SQL + 

       + 'IF @DebugFlag = 1 PRINT ''Ending Delete trigger normally: ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete') + ', nest level = '' + cast(@NestLevel as varchar)' + Char(13) + Char(10) + Char(13) + Char(10)

       + '-----' + Char(13) + Char(10) + Char(13) + Char(10)

       + ' End Try ' + Char(13) + Char(10)
       + ' Begin Catch ' + Char(13) + Char(10)
       + '   DECLARE @ErrorMessage NVARCHAR(4000), @ErrorSeverity INT, @ErrorState INT, @ErrorLine INT;' + Char(13) + Char(10) 

       + '   SET @ErrorMessage = ERROR_MESSAGE();  ' + Char(13) + Char(10)
       + '   SET @ErrorSeverity = ERROR_SEVERITY(); ' + Char(13) + Char(10) 
       + '   SET @ErrorState = ERROR_STATE();  ' + Char(13) + Char(10)
       + '   SET @ErrorLine = ERROR_LINE();  ' + Char(13) + Char(10)
       + '   RAISERROR(@ErrorMessage,@ErrorSeverity,@ErrorState)' + case when @WithLogFlag = 1 then ' with log;' else ';' end + Char(13) + Char(10) 
       + '   PRINT ''Error Line: '' + cast(@ErrorLine as varchar);' + Char(13) + Char(10)
       + ' End Catch ' 

EXEC (@SQL)

SET @SQL = quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete')

EXEC sp_settriggerorder 
  @triggername= @SQL, 
  @order='Last', 
  @stmttype = 'DELETE';

END --If @LogDelete > 0

--------------------------------------------------------------------------------------------
-- build _Deleted view
print '	Creating _Deleted view'

SET @SQL = 'CREATE VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @DeletedViewSuffix) + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns details about the rows that have been deleted in the referenced table.' + Char(13) + Char(10) + Char(13) + Char(10)

SELECT @SQL = @SQL + 
'WITH	MostRecentDeletes ' + Char(13) + Char(10)
+ 'AS ' + Char(13) + Char(10)
+ '		(SELECT		PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5, ' + Char(13) + Char(10)
+ '					max([RowVersion]) AS [RowVersion] ' + Char(13) + Char(10)
+ '		FROM		' + quotename(@AuditSchema) + '.AuditHeader ' + Char(13) + Char(10)
+ '		WHERE		TableName = ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''' ' + Char(13) + Char(10)--no quotename here
+ '			AND		Operation = ''d'' ' + Char(13) + Char(10)
+ '		GROUP BY	PrimaryKey, PrimaryKey2, PrimaryKey3, PrimaryKey4, PrimaryKey5) ' + Char(13) + Char(10)

+ 'SELECT' + Char(13) + Char(10)
----for the table's primary key column(s)
--+ '		PivotData.PrimaryKey AS ' + quotename(@PKColumnName) + Char(13) + Char(10)
+ @PKColumnsForDeletedView + Char(13) + Char(10)

--for each column
SELECT @SQL = @SQL +
--		case when c.column_id > 1 then '		,' else '		' end + 
		'		,PivotData.[' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id

--the next two joins are to exclude PK columns
		left join	sys.indexes i
			on		t.object_id = i.object_id
			and		i.is_primary_key = 1 
		left join	sys.index_columns ic
			on		i.object_id = ic.object_id
			and		i.index_id = ic.index_id
			and		c.column_id = ic.column_id

      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND ic.column_id is null
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

SELECT @SQL = @SQL +
+ '		,SysUser as DeletedBy ' + Char(13) + Char(10)
+ '		,CASE WHEN mrd.[RowVersion] = PivotData.HRowVersion then 1 else 0 end AS MostRecentDeleteFlag'  + Char(13) + Char(10)
+ '		,''' + ISNULL(@RowHistoryViewScope ,'Active') + ''' AS ViewScope' + Char(13) + Char(10)
+ '		,RowHistorySource' + Char(13) + Char(10)
+ 'FROM 	(SELECT		AH.AuditHeaderID, '  + Char(13) + Char(10)
+ '					AH.PrimaryKey, '  + Char(13) + Char(10)
+ '					AH.PrimaryKey2, '  + Char(13) + Char(10)
+ '					AH.PrimaryKey3, '  + Char(13) + Char(10)
+ '					AH.PrimaryKey4, '  + Char(13) + Char(10)
+ '					AH.PrimaryKey5, '  + Char(13) + Char(10)
+ '					AH.[RowVersion] AS HRowVersion, '  + Char(13) + Char(10)
+ '					AH.[SysUser] AS SysUser, '  + Char(13) + Char(10)
+ '					SUBSTRING(AD.ColumnName,2,LEN(AD.ColumnName)-2) AS ColumnName, '  + Char(13) + Char(10)
+ '					ISNULL(AD.NewValue,AD.OldValue) AS NewValue'  + Char(13) + Char(10)
+ '					,' + CASE ISNULL(@RowHistoryViewScope ,'Active') 
							WHEN 'All' THEN 'AH.[Source]'
							ELSE '''' + ISNULL(@RowHistoryViewScope ,'Active') + ''''
						END + ' AS RowHistorySource' + Char(13) + Char(10)
+ '		FROM		' + quotename(@AuditSchema) + '.' + 
			CASE ISNULL(@RowHistoryViewScope ,'Active') 
				WHEN 'All' THEN '[vAuditHeaderAll]'
				WHEN 'Active' THEN '[AuditHeader]'
				WHEN 'Archive' THEN '[AuditHeaderArchive]'
				ELSE '[AuditHeader]'
			END
+ ' AS AH'  + Char(13) + Char(10)
+ '		LEFT JOIN	' + quotename(@AuditSchema) + '.' +
			CASE @RowHistoryViewScope 
				WHEN 'All' THEN '[vAuditDetailAll]'
				WHEN 'Active' THEN '[AuditDetail]'
				WHEN 'Archive' THEN '[AuditDetailArchive]'
				ELSE '[AuditDetail]'
			END
+ ' AS AD'  + Char(13) + Char(10)
+ '			ON		AH.AuditHeaderID = AD.AuditHeaderID'  + Char(13) + Char(10)
+ '		WHERE		AH.TableName=''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''''  + Char(13) + Char(10)--no quotename here
+ '			AND		AH.Operation=''d'') AS AD'  + Char(13) + Char(10)
+ '		PIVOT		(MAX (NewValue)'  + Char(13) + Char(10)
+ '			FOR		ColumnName IN'  + Char(13) + Char(10)
+ '					('  + Char(13) + Char(10)
--for each column
SELECT @SQL = @SQL +
		'					' + case when c.column_id > 1 then ',' else '' end + '[' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

SELECT @SQL = @SQL +
'					)'  + Char(13) + Char(10)
+ '					) AS PivotData'  + Char(13) + Char(10)
+ 'LEFT JOIN 	MostRecentDeletes mrd'  + Char(13) + Char(10)
+ '	ON 		PivotData.PrimaryKey = mrd.PrimaryKey'  + Char(13) + Char(10)
+ '	AND 	isnull(PivotData.PrimaryKey2,'''') = isnull(mrd.PrimaryKey2,'''')'  + Char(13) + Char(10)
+ '	AND 	isnull(PivotData.PrimaryKey3,'''') = isnull(mrd.PrimaryKey3,'''')'  + Char(13) + Char(10)
+ '	AND 	isnull(PivotData.PrimaryKey4,'''') = isnull(mrd.PrimaryKey4,'''')'  + Char(13) + Char(10)
+ '	AND 	isnull(PivotData.PrimaryKey5,'''') = isnull(mrd.PrimaryKey5,'''')'  + Char(13) + Char(10)
+ '	AND 	PivotData.HRowVersion = mrd.[RowVersion]'  + Char(13) + Char(10)

IF @CreateDeletedView = 1
	EXEC (@SQL)

--------------------------------------------------------------------------------------------
-- build RowHistory view
print '	Creating _RowHistory view'

SET @SQL = 'CREATE VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix) + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This view returns historical record entries for the referenced table.' + Char(13) + Char(10) + Char(13) + Char(10)


SELECT @SQL = @SQL + 
'SELECT' + Char(13) + Char(10)
--for the table's row info columns
+ '		PivotData.AuditDate'+ Char(13) + Char(10)
+ '		,PivotData.Operation'+ Char(13) + Char(10)
+ '		,PivotData.HRowVersion AS [RowVersion]' + Char(13) + Char(10)

;With ColumnInfo as (
Select top 100000 quotename(sc.name) + ' ' + 
				Char(13) + Char(10) as TheColumn
		,isnull(sik.index_column_id,2147483647) as PrimarySort
		,sc.column_id	
		, row_number() over (order by isnull(sik.index_column_id,2147483647)) PKOrder			
	from		sys.tables as t
	inner join	sys.columns sc
		on		t.object_id = sc.object_id
	inner join	sys.types as ty
		on		ty.user_type_id = sc.user_type_id
	inner join	sys.schemas as s
		on		s.schema_id = t.schema_id
	left join	sys.key_constraints as kc
		on		t.object_id = kc.parent_object_id
		and		kc.type = 'PK'
	left join	sys.index_columns sik 
		on		t.object_id = sik.object_id 
		and		kc.unique_index_id = sik.index_id
		and		sc.column_id = sik.column_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND sc.is_computed = 0
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList like '%[[]' + sc.name + ']%')
order by	isnull(sik.index_column_id,2147483647),
			sc.column_id
	)
Select	@SQL = @SQL +	 
		'		,PivotData.' + 'PrimaryKey' + Case PKOrder when 1 then '' else cast(PKOrder as varchar(1)) end + ' AS ' + TheColumn + Char(13) + Char(10)
From		ColumnInfo
order by	column_id
	
--for each non-PK column
SELECT @SQL = @SQL +
		'		,PivotData.[' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
        AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
        AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
        AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
        AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

SELECT @SQL = @SQL +
+ '		,''' + ISNULL(@RowHistoryViewScope ,'Active') + ''' AS ViewScope' + Char(13) + Char(10)
+ '		,RowHistorySource' + Char(13) + Char(10)
+ '		,[SysUser] ' + Char(13) + Char(10)
+ '		,[Application] ' + Char(13) + Char(10)
+ '		,[SQLStatement] ' + Char(13) + Char(10)
+ 'FROM 	(SELECT		AH.AuditHeaderID '  + Char(13) + Char(10)
+ '					,AH.PrimaryKey '  + Char(13) + Char(10)
+ '					,AH.PrimaryKey2 '  + Char(13) + Char(10)
+ '					,AH.PrimaryKey3 '  + Char(13) + Char(10)
+ '					,AH.PrimaryKey4 '  + Char(13) + Char(10)
+ '					,AH.PrimaryKey5 '  + Char(13) + Char(10)
+ '					,AH.AuditDate '  + Char(13) + Char(10)
+ '					,AH.Operation '  + Char(13) + Char(10)
+ '					,AH.[RowVersion] AS HRowVersion '  + Char(13) + Char(10)
+ '					,SUBSTRING(AD.ColumnName,2,LEN(AD.ColumnName)-2) AS ColumnName '  + Char(13) + Char(10)
+ '					,ISNULL(AD.NewValue,AD.OldValue) AS NewValue' + Char(13) + Char(10)
+ '					,' + CASE ISNULL(@RowHistoryViewScope ,'Active') 
							WHEN 'All' THEN 'AH.[Source]'
							ELSE '''' + ISNULL(@RowHistoryViewScope ,'Active') + ''''
						END + ' AS RowHistorySource' + Char(13) + Char(10)
+ '					,AH.[SysUser] '  + Char(13) + Char(10)
+ '					,AH.[Application] '  + Char(13) + Char(10)
+ '					,AH.[SQLStatement] '  + Char(13) + Char(10)
+ '		FROM		' + quotename(@AuditSchema) + '.' + 
			CASE ISNULL(@RowHistoryViewScope ,'Active') 
				WHEN 'All' THEN '[vAuditHeaderAll]'
				WHEN 'Active' THEN '[AuditHeader]'
				WHEN 'Archive' THEN '[AuditHeaderArchive]'
				ELSE '[AuditHeader]'
			END
+ ' AS AH'  + Char(13) + Char(10)
+ '		LEFT JOIN	' + quotename(@AuditSchema) + '.' +
			CASE @RowHistoryViewScope 
				WHEN 'All' THEN '[vAuditDetailAll]'
				WHEN 'Active' THEN '[AuditDetail]'
				WHEN 'Archive' THEN '[AuditDetailArchive]'
				ELSE '[AuditDetail]'
			END
+ ' AS AD'  + Char(13) + Char(10)
+ '			ON		AH.AuditHeaderID = AD.AuditHeaderID'  + Char(13) + Char(10)
+ '		WHERE		AH.TableName=''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''''  + Char(13) + Char(10)--no quotename here
+ '					) AS AD'  + Char(13) + Char(10)
+ '		PIVOT		(MAX (NewValue)'  + Char(13) + Char(10)
+ '			FOR		ColumnName IN'  + Char(13) + Char(10)
+ '					('  + Char(13) + Char(10)
--for each column
SELECT @SQL = @SQL +
		'					' + case when c.column_id > 1 then ',' else '' end + '[' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

SELECT @SQL = @SQL +
'					)'  + Char(13) + Char(10)
+ '					) AS PivotData'  + Char(13) + Char(10)

IF @CreateRowHistoryView = 1
	EXEC (@SQL)

--------------------------------------------------------------------------------------------
-- build _RowHistory Table-Valued UDF

SET @SQL = 'CREATE FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @RowHistoryFunctionSuffix) + Char(13) + Char(10) + '			(' + Char(13) + Char(10)
SET @SQL = @SQL + '			' + substring('@PK varchar(36),@PK2 varchar(36),@PK3 varchar(36),@PK4 varchar(36),@PK5 varchar(36)',1,15 + (@PKColumnQty - 1) * 17) + Char(13) + Char(10)
SET @SQL = @SQL + '			)' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This function retrieves data from the RowHistory view for the referenced table for the record identified by the PK parameters.' + Char(13) + Char(10) + Char(13) + Char(10)


IF not (@LogInsert = 2 and @LogUpdate = 2 and @LogDelete = 2)

 SET @SQL = @SQL 
       + 'RETURNS TABLE ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + 'RETURN ' + Char(13) + Char(10)
       + '( ' + Char(13) + Char(10)
       + '-- Retrieve the basic logged data through the _RowHistory view' + Char(13) + Char(10)
       + '-- Detailed data retrieval is not possible because full logging has not been configured for this table.' + Char(13) + Char(10)
       + 'SELECT		*' + Char(13) + Char(10) 
       + 'FROM		' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix) + Char(13) + Char(10) 
       + @RowHistoryUDFFilter  + Char(13) + Char(10) 
       + ') ' + Char(13) + Char(10)

Else
	Begin
 SET @SQL = @SQL 
       + 'RETURNS @HistoryData Table' + Char(13) + Char(10)
       + '(' + Char(13) + Char(10) 
       + 'AuditDate datetime' + Char(13) + Char(10)
       + ',Operation varchar(1)' + Char(13) + Char(10)
       + ',[RowVersion] int' + Char(13) + Char(10)



 --add dynamic columns to table variable definition
Select	@SQL = @SQL
		+ ',' + quotename(c.name) + ty.name + 
		case	when  ty.name in ('nchar','nvarchar','char','varchar') then ' (' + isnull(nullif(cast(c.max_length as varchar(10)),'-1'),'max') + ')'
				when  ty.name in ('numeric','decimal') then ' (' + cast(c.precision as varchar(10)) + ',' + + cast(c.scale as varchar(10)) + ')'
				else ''
				end + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id

SET @SQL = @SQL 
 
       + ',ViewScope varchar(10)' + Char(13) + Char(10)
       + ',RowHistorySource varchar(10)' + Char(13) + Char(10)
       + ',SysUser sysname' + Char(13) + Char(10)
       + ',[Application] varchar(128)' + Char(13) + Char(10)
       + ',SQLStatement varchar(max)' + Char(13) + Char(10)
       + ') ' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10)
       + 'BEGIN ' + Char(13) + Char(10) + Char(13) + Char(10)
       + '-- Detailed data retrieval is enabled for this table.' + Char(13) + Char(10)
       + 'With	AuditDataExtract --Source data query' + Char(13) + Char(10)
       + '	AS' + Char(13) + Char(10)
       + '	(' + Char(13) + Char(10)
       + '	SELECT		*' + Char(13) + Char(10)
       + '	FROM		' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix) + Char(13) + Char(10) 
       + '	' + @RowHistoryUDFFilter  + Char(13) + Char(10) 
       + '	),' + Char(13) + Char(10)
       + '	CurrentRowExtract ' + Char(13) + Char(10)
       + '	AS' + Char(13) + Char(10)
       + '	(' + Char(13) + Char(10)
       + '	Select	getdate() as AuditDate' + Char(13) + Char(10)
       + '			,''c'' as Operation' + Char(13) + Char(10)
       + '			,(Select isnull(max([RowVersion]),0) + 1 from AuditDataExtract) as [RowVersion]' + Char(13) + Char(10)


	--add the pk column references
	SELECT @SQL = @SQL + '			,' + quotename(c.name) + Char(13) + Char(10)
	  from   sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id

--for each column
SELECT @SQL = @SQL +
		'			,cast([' + c.name + '] as varchar(50)) as [' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
         AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id


SELECT @SQL = @SQL +
         '			,null as ViewScope' + Char(13) + Char(10)
       + '			,null as RowHistorySource' + Char(13) + Char(10)
       + '			,null as SysUser' + Char(13) + Char(10)
       + '			,null as [Application]' + Char(13) + Char(10)
       + '			,null as SQLStatement' + Char(13) + Char(10)
       + '			from	[' + @SchemaName + '].[' + @TableName + ']' + Char(13) + Char(10)
       + '	' + @RowHistoryUDFFilter  + Char(13) + Char(10) 
       + '			),' + Char(13) + Char(10)
       + '			RowHistoryExtract' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			Select * from AuditDataExtract' + Char(13) + Char(10)
       + '			Union All' + Char(13) + Char(10)
       + '			Select * from CurrentRowExtract' + Char(13) + Char(10)
       + '			),' + Char(13) + Char(10)
       + '			RowHistory' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			--Anchor query for RowHistory buildup. Get the most current rowversion' + Char(13) + Char(10)
       + '			Select		top 1 *' + Char(13) + Char(10)
       + '			From		RowHistoryExtract' + Char(13) + Char(10)
       + '			order by	[RowVersion] desc' + Char(13) + Char(10) + Char(13) + Char(10)
       + '			UNION All' + Char(13) + Char(10)
       + '			--Recursive query for RowHistory buildup' + Char(13) + Char(10)
       + '			Select		NextVersion.AuditDate' + Char(13) + Char(10)
       + '						,NextVersion.Operation' + Char(13) + Char(10)
       + '						,NextVersion.[RowVersion]' + Char(13) + Char(10)

	--for each PK column
	SELECT @SQL = @SQL +
		'						,isnull(NextVersion.[' + c.name + '] , PreviousVersion.[' + c.name + '])' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id

	--for each non-PKcolumn
	SELECT @SQL = @SQL +
		'						,isnull(NextVersion.[' + c.name + '] , PreviousVersion.[' + c.name + '])' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
         AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id


 	SELECT @SQL = @SQL +
       + '						,NextVersion.ViewScope' + Char(13) + Char(10)
       + '						,NextVersion.RowHistorySource' + Char(13) + Char(10)
       + '						,NextVersion.SysUser' + Char(13) + Char(10)
       + '						,NextVersion.[Application]' + Char(13) + Char(10)
       + '						,NextVersion.SQLStatement' + Char(13) + Char(10)
       + '			from		RowHistoryExtract as NextVersion' + Char(13) + Char(10)
       + '			Inner join	RowHistory as PreviousVersion' + Char(13) + Char(10)
       + '				on		PreviousVersion.[RowVersion] = NextVersion.[RowVersion] + 1' + Char(13) + Char(10)


	--for each PK column
	SELECT @SQL = @SQL +
		'				and		PreviousVersion.' + '[' + c.name + '] = NextVersion.' + '[' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id


  	SELECT @SQL = @SQL +
       + '			)' + Char(13) + Char(10)
       + '-- Statement that executes the CTE' + Char(13) + Char(10)
       + 'Insert into @HistoryData' + Char(13) + Char(10)
       + '	--Returns the function table' + Char(13) + Char(10)
       + '	Select	AuditDate' + Char(13) + Char(10)
       + '			,Operation' + Char(13) + Char(10)
       + '			,[RowVersion]' + Char(13) + Char(10)

		--add the pk column references
		;With PKs
			as
			(
			Select quotename(c.name) as PKName, c.column_id, row_number() over (order by c.column_id) PKOrder
			from	sys.tables as t
			join	sys.columns as c
			  on	t.object_id = c.object_id
			join	sys.schemas as s
			  on	s.schema_id = t.schema_id
			join	sys.types as ty
			  on	ty.user_type_id = c.user_type_id
			where	t.name = @TableName AND s.name = @SchemaName 
			 AND	c.is_computed = 0
			 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
			 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
			 AND	(@PKColumnNameList like '%[[]' + c.name + ']%') 
			), PKCols
			as
			(
			SELECT '			,' + PKName as PKCol, column_id
			from	PKs
			
			),DataCols
			as
			(
			--for each column
			SELECT 
				'			, nullif(' + quotename(c.name) + ',''<-null->'')' as DataCol, c.column_id
			from	sys.tables as t
			join	sys.columns as c
			  on	t.object_id = c.object_id
			join	sys.schemas as s
			  on	s.schema_id = t.schema_id
			join	sys.types as ty
			  on	ty.user_type_id = c.user_type_id
			where	t.name = @TableName AND s.name = @SchemaName 
			 AND	c.is_computed = 0
			 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
			 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
			 AND	(@PKColumnNameList not like '%[[]' + c.name + ']%') 
			 AND	(@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
				 ),MergeCols
				 as
				 (
				 Select PKCol as ColStatement, column_id as ColOrder from PKCols
				 union all
				 Select DataCol, column_id from DataCols
				 )
			SELECT	@SQL = @SQL + ColStatement + Char(13) + Char(10) 
			FROM	MergeCols
			order by ColOrder


		SELECT @SQL = @SQL +
				 '			,ViewScope' + Char(13) + Char(10)
			   + '			,RowHistorySource' + Char(13) + Char(10)
			   + '			,SysUser' + Char(13) + Char(10)
			   + '			,[Application]' + Char(13) + Char(10)
			   + '			,SQLStatement' + Char(13) + Char(10)
       + 'FROM		RowHistory' + Char(13) + Char(10)
       + 'where		Operation <> ''c''' + Char(13) + Char(10)
       + 'order by	[RowVersion],AuditDate' + Char(13) + Char(10)
       + 'option		(MAXRECURSION 10000)' + Char(13) + Char(10) + Char(13) + Char(10)
       + 'Return ' + Char(13) + Char(10)
       + 'END ' + Char(13) + Char(10)
	End
	

IF @CreateRowHistoryFunction = 1
	IF @CreateRowHistoryView = 1
		BEGIN
			print '	Creating _RowHistory UDF'
			--select (@SQL)
			EXEC (@SQL)
		END
	ELSE
		RAISERROR ('The _RowHistory view must exist to create the _RowHistory function.',16,0)

--------------------------------------------------------------------------------------------
-- build _TableRecovery Table-Valued UDF

SET @SQL = 'CREATE FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @TableRecoveryFunctionSuffix) + Char(13) + Char(10) + '			(' + Char(13) + Char(10)
SET @SQL = @SQL + '			@RecoveryTime datetime' + Char(13) + Char(10)
SET @SQL = @SQL + '			)' + Char(13) + Char(10) + Char(13) + Char(10) 
       + ' -- NEW generated by AutoAudit Version ' + @Version + ' on ' + Convert(VARCHAR(30), GetDate(),100)  + Char(13) + Char(10)
       + ' -- created by Paul Nielsen and John Sigouin ' + Char(13) + Char(10)
       + ' -- www.SQLServerBible.com ' + Char(13) + Char(10)
       + ' -- AutoAudit.codeplex.com ' + Char(13) + Char(10)
       + ' -- This function retrieves an image of the table as it existed at the specified point in time.' + Char(13) + Char(10) + Char(13) + Char(10)

IF not (@LogInsert = 2 and @LogUpdate = 2 and @LogDelete = 2)

 SET @SQL = @SQL 
       + 'RETURNS TABLE ' + Char(13) + Char(10) + Char(13) + Char(10) 
       + 'RETURN ' + Char(13) + Char(10)
       + '( ' + Char(13) + Char(10)
       + '-- Retrieve the basic logged data through the _RowHistory view' + Char(13) + Char(10)
       + '-- Detailed data retrieval is not possible because full logging has not been configured for this table.' + Char(13) + Char(10)
       + 'SELECT		*' + Char(13) + Char(10) 
       + 'FROM		' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix) + Char(13) + Char(10) 
       + @RowHistoryUDFFilter  + Char(13) + Char(10) 
       + ') ' + Char(13) + Char(10)

Else
	Begin
	
 --build list of columns
 Set @SQLColumns = ''
 --add dynamic columns to table variable definition
Select	@SQLColumns = @SQLColumns 
		+ ',' + quotename(c.name) + ty.name + 
		case	when  ty.name in ('nchar','nvarchar','char','varchar') then ' (' + isnull(nullif(cast(c.max_length as varchar(10)),'-1'),'max') + ')'
				when  ty.name in ('numeric','decimal') then ' (' + cast(c.precision as varchar(10)) + ',' + + cast(c.scale as varchar(10)) + ')'
				else ''
				end + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id
Select	@SQLColumns = SUBSTRING(@SQLColumns,2,len(@SQLColumns))

 SET @SQL = @SQL 
       + 'RETURNS @HistoryData Table' + Char(13) + Char(10)
       + '(' + Char(13) + Char(10) 

--add dynamic columns to table variable definition
Select	@SQL = @SQL + @SQLColumns

SET @SQL = @SQL 
       + ') ' + Char(13) + Char(10)
       + 'AS ' + Char(13) + Char(10)
       + 'BEGIN ' + Char(13) + Char(10) + Char(13) + Char(10)
       
 SET @SQL = @SQL 
       + '-- Create table variable to hold history records.' + Char(13) + Char(10)
       + 'Declare @AuditDataExtract table' + Char(13) + Char(10)
       + '	(' + Char(13) + Char(10) 
       + '	AuditDate datetime' + Char(13) + Char(10)
       + '	,Operation varchar(1)' + Char(13) + Char(10)
       + '	,[RowVersion] int' + Char(13) + Char(10)

--add PK columns to table variable definition
Select	@SQL = @SQL + 
		'	,[' + c.name + '] varchar(50)' + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
order by c.column_id

--add non-PK columns to table variable definition
Select	@SQL = @SQL + 
		'	,[' + c.name + '] varchar(50)' + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
	AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id

 
SET @SQL = @SQL 
       + '	) ' + Char(13) + Char(10) + Char(13) + Char(10)
       
       + '-- Detailed data retrieval is enabled for this table.' + Char(13) + Char(10)
       + '--write the full history for the table into a temp table variable for performance.' + Char(13) + Char(10)
       + 'Insert @AuditDataExtract ' + Char(13) + Char(10)
       + 'Select ' + Char(13) + Char(10)
       + '			AuditDate' + Char(13) + Char(10)
       + '			,Operation' + Char(13) + Char(10)
       + '			,[RowVersion]' + Char(13) + Char(10)

--add PK columns to table variable definition
Select	@SQL = @SQL +
		'			,' + quotename(c.name) + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	--AND (@ColumnNames = '<All>' or @PKColumnNameList + @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id

--add non-PK columns to table variable definition
Select	@SQL = @SQL +
		'			,' + quotename(c.name) + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
	AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id

 SET @SQL = @SQL 
       + 'FROM		' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix) + Char(13) + Char(10)  + Char(13) + Char(10) 
       + '-- Detailed data retrieval is enabled for this table.' + Char(13) + Char(10)
       + ';With	AuditDataExtract --Source data query' + Char(13) + Char(10)
       + '	AS' + Char(13) + Char(10)
       + '	(' + Char(13) + Char(10)
       + '	SELECT		*' + Char(13) + Char(10)
       + '	FROM		@AuditDataExtract' + Char(13) + Char(10) 
       + '	),' + Char(13) + Char(10)

--Add CurrentRowExtract CTE segment
       + '	CurrentRowExtract ' + Char(13) + Char(10)
       + '	AS' + Char(13) + Char(10)
       + '	(' + Char(13) + Char(10)
       + '	Select		getdate() as AuditDate' + Char(13) + Char(10)
       + '				,''c'' as Operation' + Char(13) + Char(10)
       + '				,(Select isnull(max([RowVersion]),0) + 1 from AuditDataExtract ' + Char(13) + Char(10)
       + '				Where	1=1 ' + Char(13) + Char(10)
	
	--for each PK column
	SELECT @SQL = @SQL + '					and	AuditDataExtract.' + quotename(c.name) + ' = ' 
					+ '[' + @SchemaName + '].[' + @TableName + '].' + quotename(c.name) + Char(13) + Char(10)
	  from   sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id
	
	 SET @SQL = @SQL 
	   + '				) as [RowVersion]' + Char(13) + Char(10)
	
	--add the pk column references
	SELECT @SQL = @SQL + '				,' + quotename(c.name) + Char(13) + Char(10)
	  from   sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id

--for each column
SELECT @SQL = @SQL +
		'				,cast([' + c.name + '] as varchar(50)) as [' + c.name + ']'  + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
         AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

SELECT @SQL = @SQL
       + '	from		[' + @SchemaName + '].[' + @TableName + ']' + Char(13) + Char(10)
       --+ '	' + @RowHistoryUDFFilter  + Char(13) + Char(10) 
       + '			),' + Char(13) + Char(10)

--Add RowHistoryExtract CTE segment
       + '			RowHistoryExtract' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			Select * from AuditDataExtract' + Char(13) + Char(10)
       + '			Union All' + Char(13) + Char(10)
       + '			Select * from CurrentRowExtract' + Char(13) + Char(10)
       + '			),' + Char(13) + Char(10)

--Add MostRecentRows CTE segment
       + '			MostRecentRows' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			--Get most recent rows' + Char(13) + Char(10)
       + '			Select ' + Char(13) + Char(10)
       + '						max([RowVersion]) as MostRecentRow' + Char(13) + Char(10)

	--add the pk column references
	SELECT @SQL = @SQL + '						,' + quotename(c.name) + Char(13) + Char(10)
	  from   sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id
	
 SET @SQL = @SQL 
       + '			from		RowHistoryExtract' + Char(13) + Char(10)
       + '			Group By	' + Char(13) + Char(10)

	--add the pk column references
	;With PKs
		as
		(
		Select quotename(c.name) as PKName, c.column_id, row_number() over (order by c.column_id) PKOrder
		from   sys.tables as t
		join	sys.columns as c
		  on	t.object_id = c.object_id
		join	sys.schemas as s
		  on	s.schema_id = t.schema_id
		join	sys.types as ty
		  on	ty.user_type_id = c.user_type_id
		where	t.name = @TableName AND s.name = @SchemaName 
		 AND	c.is_computed = 0
		 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
		 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
		 AND	(@PKColumnNameList like '%[[]' + c.name + ']%') 
		)

	SELECT @SQL = @SQL + '						' + case when PKOrder > 1 then ',' else '' end + PKName + Char(13) + Char(10)
	from	PKs
	order by PKOrder

 SET @SQL = @SQL 
       + '			),' + Char(13) + Char(10)

--Add RowHistory CTE segment
       + '			RowHistory' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			--Anchor query for RowHistory buildup. Get the most current rowversion' + Char(13) + Char(10)
--       + '			Select		RowHistoryExtract.*' + Char(13) + Char(10)
       + '			Select		' + Char(13) + Char(10)


       + '			RowHistoryExtract.AuditDate' + Char(13) + Char(10)
       + '			,RowHistoryExtract.Operation' + Char(13) + Char(10)
       + '			,RowHistoryExtract.[RowVersion]' + Char(13) + Char(10)

--add PK columns to table variable definition
Select	@SQL = @SQL +
		'			,RowHistoryExtract.' + quotename(c.name) + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
order by c.column_id

--add non-PK columns to table variable definition
Select	@SQL = @SQL + 
		'			,RowHistoryExtract.' + quotename(c.name) + Char(13) + Char(10)
from	sys.tables as t
join	sys.columns as c
  on	t.object_id = c.object_id
join	sys.schemas as s
  on	s.schema_id = t.schema_id
join	sys.types as ty
  on	ty.user_type_id = c.user_type_id
where	t.name = @TableName AND s.name = @SchemaName 
	AND c.is_computed = 0
	AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
	AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
	AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
	AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
order by c.column_id




Select	@SQL = @SQL + 
       + '			From		RowHistoryExtract' + Char(13) + Char(10)
       + '			inner join	MostRecentRows' + Char(13) + Char(10) 
       + '				on		RowHistoryExtract.[RowVersion] = MostRecentRows.MostRecentRow' + Char(13) + Char(10)

	--for each PK column
	SELECT @SQL = @SQL +
		'				and		RowHistoryExtract.' + quotename(c.name) + ' = MostRecentRows.' + quotename(c.name) + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id
       
 SET @SQL = @SQL 
       + '			UNION All' + Char(13) + Char(10)
       + '			--Recursive query for RowHistory buildup' + Char(13) + Char(10)
       + '			Select		NextVersion.AuditDate' + Char(13) + Char(10)
       + '						,NextVersion.Operation' + Char(13) + Char(10)
       + '						,NextVersion.[RowVersion]' + Char(13) + Char(10)


	--add the pk column references
	SELECT @SQL = @SQL +
	'						,isnull(NextVersion.' + quotename(c.name) + ' , PreviousVersion.' + quotename(c.name) + ')' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id

	--for each non-PK column
	SELECT @SQL = @SQL +
		'						,isnull(NextVersion.' + quotename(c.name) + ' , PreviousVersion.' + quotename(c.name) + ')' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList not like '%[[]' + c.name + ']%') 
         AND (@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
	  order by c.column_id

 	SET @SQL = @SQL
       + '			from		RowHistoryExtract as NextVersion' + Char(13) + Char(10)
       + '			Inner join	RowHistory as PreviousVersion' + Char(13) + Char(10)
       + '				on		PreviousVersion.[RowVersion] = NextVersion.[RowVersion] + 1' + Char(13) + Char(10)

	--for each PK column
	SELECT @SQL = @SQL +
		'				and		PreviousVersion.' + quotename(c.name) + ' = NextVersion.' + quotename(c.name) + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id


  	SELECT @SQL = @SQL +
       + '			),' + Char(13) + Char(10)

--Add RowsOfInterest CTE segment
       + '			RowsOfInterest' + Char(13) + Char(10)
       + '			AS' + Char(13) + Char(10)
       + '			(' + Char(13) + Char(10)
       + '			--Get Rows Of Interest' + Char(13) + Char(10)
       + '			Select		max([RowVersion]) as [RowVersion]' + Char(13) + Char(10)

--add the pk column references
	SELECT @SQL = @SQL + '						,' + quotename(c.name) + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id
	
 SET @SQL = @SQL 
       + '			from		RowHistory' + Char(13) + Char(10)
       + '			Where		[AuditDate] <= @RecoveryTime' + Char(13) + Char(10)
       + '				And		Operation <> ''c''' + Char(13) + Char(10)
       + '			Group By		' + Char(13) + Char(10)

	--add the pk column references
	;With PKs
		as
		(
		Select quotename(c.name) as PKName, c.column_id, row_number() over (order by c.column_id) PKOrder
		from   sys.tables as t
		join	sys.columns as c
		  on	t.object_id = c.object_id
		join	sys.schemas as s
		  on	s.schema_id = t.schema_id
		join	sys.types as ty
		  on	ty.user_type_id = c.user_type_id
		where	t.name = @TableName AND s.name = @SchemaName 
		 AND	c.is_computed = 0
		 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
		 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
		 AND	(@PKColumnNameList like '%[[]' + c.name + ']%') 
		)

	SELECT @SQL = @SQL + '						' + case when PKOrder > 1 then ',' else '' end + PKName + Char(13) + Char(10)
	from	PKs
	order by PKOrder

 SET @SQL = @SQL 
       + '			)' + Char(13) + Char(10)

--Add Statement that executes the CTE segment
       + '-- Statement that executes the CTE' + Char(13) + Char(10)
       + 'Insert into @HistoryData' + Char(13) + Char(10)
       + '--Returns the function table' + Char(13) + Char(10)
       + 'Select ' + Char(13) + Char(10)	

		--add the pk column references
		;With PKs
			as
			(
			Select quotename(c.name) as PKName, c.column_id, row_number() over (order by c.column_id) PKOrder
			from	sys.tables as t
			join	sys.columns as c
			  on	t.object_id = c.object_id
			join	sys.schemas as s
			  on	s.schema_id = t.schema_id
			join	sys.types as ty
			  on	ty.user_type_id = c.user_type_id
			where	t.name = @TableName AND s.name = @SchemaName 
			 AND	c.is_computed = 0
			 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
			 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
			 AND	(@PKColumnNameList like '%[[]' + c.name + ']%') 
			), PKCols
			as
			(
			SELECT '			' + case when column_id = 1 then '' else ',' end + 'rh.' + PKName + '' as PKCol, column_id
			from	PKs
			),DataCols
			as
			(
			--for each column
			SELECT 
				'			' + case when c.column_id = 1 then '' else ',' end + 'nullif(rh.' + quotename(c.name) + ',''<-null->'')' as DataCol, c.column_id
			from	sys.tables as t
			join	sys.columns as c
			  on	t.object_id = c.object_id
			join	sys.schemas as s
			  on	s.schema_id = t.schema_id
			join	sys.types as ty
			  on	ty.user_type_id = c.user_type_id
			where	t.name = @TableName AND s.name = @SchemaName 
			 AND	c.is_computed = 0
			 AND	c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
			 AND	ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
			 AND	(@PKColumnNameList not like '%[[]' + c.name + ']%') 
			 AND	(@ColumnNames = '<All>' or @ColumnNames like '%[[]' + c.name + ']%') 
				 ),MergeCols
				 as
				 (
				 Select PKCol as ColStatement, column_id as ColOrder from PKCols
				 union all
				 Select DataCol, column_id from DataCols
				 )
			SELECT	@SQL = @SQL + ColStatement + Char(13) + Char(10) 
			FROM	MergeCols
			order by ColOrder

		SET @SQL = @SQL 
       + 'FROM		RowHistory as rh' + Char(13) + Char(10)
       + 'Inner join	RowsOfInterest as roi' + Char(13) + Char(10)
       + '	on		rh.[RowVersion] = roi.[RowVersion]' + Char(13) + Char(10)

	--for each PK column
	SELECT @SQL = @SQL +
		'	and		rh.' + '[' + c.name + '] = roi.' + '[' + c.name + ']' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id


	SET @SQL = @SQL 
        + 'Where		Operation <> ''d''' + Char(13) + Char(10)
        + 'order by ' + Char(13) + Char(10)


	--for each PK column
	SELECT @SQL = @SQL +
		'			rh.' + '[' + c.name + '],' + Char(13) + Char(10)
	  from sys.tables as t
		join sys.columns as c
		  on t.object_id = c.object_id
		join sys.schemas as s
		  on s.schema_id = t.schema_id
		join sys.types as ty
		  on ty.user_type_id = c.user_type_id
      where t.name = @TableName AND s.name = @SchemaName 
         AND c.is_computed = 0
         AND c.name NOT IN (@CreatedColumnName, @ModifiedColumnName, @CreatedByColumnName, @ModifiedByColumnName, @RowVersionColumnName)
         AND ty.name NOT IN ('text', 'ntext', 'image', 'geography', 'xml', 'binary', 'varbinary', 'timestamp', 'rowversion')
         AND (@PKColumnNameList like '%[[]' + c.name + ']%') 
	  order by c.column_id
       
       
 	SELECT @SQL = @SQL
       + '			rh.[RowVersion],' + Char(13) + Char(10)
       + '			rh.AuditDate' + Char(13) + Char(10)
       + 'option		(MAXRECURSION 10000)' + Char(13) + Char(10) + Char(13) + Char(10)
       + 'Return ' + Char(13) + Char(10)
       + 'END ' + Char(13) + Char(10)
	End
	

IF @CreateRowHistoryFunction = 1
	IF @CreateRowHistoryView = 1
		IF (@LogInsert = 2 and @LogUpdate = 2 and @LogDelete = 2)
			BEGIN
				print '	Creating _TableRecovery UDF'
				--select (@SQL)
				EXEC (@SQL)
			END
		Else
			RAISERROR ('	Error - @LogInsert, @LogUpdate and @LogDelete MUST all = 2 to create _TableRecovery function.',0,0)
	ELSE
		RAISERROR ('	Error - The _RowHistory view must exist to create the _RowHistory function.',0,0)

--save base table AutoAudit settings to AuditBaseTables table
--a merge (upsert) query would be nice here but not compatible with sql 2005
SET @SQL = 'IF EXISTS (Select 1 from ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ 'WHERE	[SchemaName] = ''' + @SchemaName + ''''
	+ '	AND [TableName] = ''' + @TableName + ''')' + Char(13) + Char(10)
	+ 'UPDATE ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ 'SET [StrictUserContext] = ' + CAST(@StrictUserContext AS VARCHAR) + ','
	+ ' [LogSQL] = ' + CAST(@LogSQL AS VARCHAR) + ','
	+ ' [BaseTableDDL] = ' + CAST(@BaseTableDDL AS VARCHAR) + ','
	+ ' [LogInsert] = ' + CAST(@LogInsert AS VARCHAR) + ','
	+ ' [LogUpdate] = ' + CAST(@LogUpdate AS VARCHAR) + ','
	+ ' [LogDelete] = ' + CAST(@LogDelete AS VARCHAR) + ','
	+ ' [ViewSchema] = ''' + @ViewSchema + ''','
	+ ' [ColumnNames] = ''' + @ColumnNames + ''''
	+ ' OUTPUT deleted.ViewSchema into #ViewSchema '
	+ ' WHERE [SchemaName] = ''' + @SchemaName + ''''
	+ ' AND [TableName] = ''' + @TableName + '''' + Char(13) + Char(10)
	+ 'ELSE ' + Char(13) + Char(10)
	+ 'Insert ' + quotename(@AuditSchema) + '.[AuditBaseTables] '
	+ ' ([SchemaName],[TableName],[StrictUserContext],[LogSQL],[BaseTableDDL],[LogInsert],[LogUpdate],[LogDelete],[EnabledFlag],[ViewSchema],[ColumnNames]) '
	+ 'VALUES (''' + @SchemaName + ''','
	+ '''' + @TableName + ''','
	+ CAST(@StrictUserContext AS VARCHAR) + ','
	+ CAST(@LogSQL AS VARCHAR) + ','
	+ CAST(@BaseTableDDL AS VARCHAR) + ','
	+ CAST(@LogInsert AS VARCHAR) + ','
	+ CAST(@LogUpdate AS VARCHAR) + ','
	+ CAST(@LogDelete AS VARCHAR) + ','
	+ ' 1, '
	+ '''' + @ViewSchema + ''','
	+ '''' + @ColumnNames + ''')'
	
EXEC (@SQL)

Set context_info 0x0;

raiserror ('',0,0) with nowait --to flush out the print statements

RETURN -- END OF pAutoAudit SPROC

go --------------------------------------------------------------------

--**************** Setup Script Section #8 ****************
-- Create other Stored Procedures
--*********************************************************

Print 'Creating Stored Procedure - pAutoAuditRebuild'
go
CREATE PROC pAutoAuditRebuild (
   @SchemaName sysname = 'dbo',  --the schema of the table to rebuild
   @TableName sysname  --the tablename to rebuild
	) 
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to rebuild AutoAudit triggers for the specified table based on the settings saved in the AuditBaseTables table.

SET NoCount ON

DECLARE
   @StrictUserContext	BIT,		-- 2.00 if 0 then permits DML setting of Created, CreatedBy, Modified, ModifiedBy
   @LogSQL				BIT,
   @BaseTableDDL		BIT,		-- 0 = don't add audit columns to base table, 1 = add audit columns to base table
   @LogInsert			TINYINT,	-- 0 = nothing, 1 = header only, 2 = header and detail
   @LogUpdate			TINYINT,	-- 0 = nothing, 1 = header only, 2 = header and detail
   @LogDelete			TINYINT,	-- 0 = nothing, 1 = header only, 2 = header and detail
   @ColumnNames			NVARCHAR(max),  --columns to include when logging details (@Log...=2). Default = '<All>'. Format: '[Col1],[Col2],...'
   @SQL					NVARCHAR(max)

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50)
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'
   
--retrieve base table AutoAudit settings from AuditBaseTables table
SELECT	@StrictUserContext = StrictUserContext,
		@LogSQL = LogSQL,
		@BaseTableDDL = BaseTableDDL,
		@LogInsert = LogInsert,
		@LogUpdate = LogUpdate,
		@LogDelete = LogDelete,
		@ColumnNames = ColumnNames
FROM	[AuditBaseTables]
WHERE	[SchemaName] = @SchemaName
	AND	[TableName] = @TableName;

IF @@rowcount = 0
	BEGIN
		--RAISERROR ('INFO - AutoAudit cannot be rebuilt for table [%s].[%s] because it''s settings don''t exist in the AuditBaseTables table.',0,0,@SchemaName,@TableName);
		RETURN
	END
ELSE
	PRINT 'Rebuilding AutoAudit for table: ' + quotename(@SchemaName) + '.' + quotename(@TableName) 
	SET @SQL = 'EXEC ' + quotename(@AuditSchema) + '.pAutoAudit' + Char(13) + Char(10)
+ '			@SchemaName = ''' + @SchemaName + ''',' + Char(13) + Char(10)
+ '			@TableName = ''' + @TableName + ''',' + Char(13) + Char(10)
+ '			@StrictUserContext = ' + cast(@StrictUserContext as varchar) + ',' + Char(13) + Char(10)
+ '			@LogSQL = ' + cast(@LogSQL as varchar) + ',' + Char(13) + Char(10)
+ '			@BaseTableDDL = ' + cast(@BaseTableDDL as varchar) + ',' + Char(13) + Char(10)
+ '			@LogInsert = ' + cast(@LogInsert as varchar) + ',' + Char(13) + Char(10)
+ '			@LogUpdate = ' + cast(@LogUpdate as varchar) + ',' + Char(13) + Char(10)
+ '			@LogDelete = ' + cast(@LogDelete as varchar) + ',' + Char(13) + Char(10)
+ '			@ColumnNames = ''' + @ColumnNames + ''';' + Char(13) + Char(10)
EXEC (@SQL)

go --------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditRebuildAll'
go

CREATE PROC [pAutoAuditRebuildAll] 

AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to rebuild AutoAudit triggers for ALL tables that are currently setup with AutoAudit based on the settings saved in the AuditBaseTables table.

SET NoCount ON 

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50)
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'

DECLARE 
   @TableName sysname, 
   @SchemaName sysname, 
   @SQL NVARCHAR(max)

--save the list or tables to a temp table to prevent a cursor issue
SELECT	SchemaName, TableName
INTO	#Tables
FROM	AuditBaseTables
EXCEPT
SELECT	SchemaName, TableName
FROM	AuditAllExclusions

-- for each table
-- 1
DECLARE cTables CURSOR FAST_FORWARD READ_ONLY
  FOR  SELECT SchemaName, TableName 
			  from #Tables
       INTERSECT
       SELECT Schema_Name([schema_id]), [name] as TableName
       FROM sys.objects where type = 'U'
       Order by 1,2
--2 
OPEN cTables
--3 
FETCH cTables INTO @SchemaName, @TableName   -- prime the cursor
WHILE @@Fetch_Status = 0 
  BEGIN
		SET @SQL = 'EXEC ' + quotename(@AuditSchema) + '.pAutoAuditRebuild ''' + @SchemaName + ''', ''' + @TableName + ''''

		EXEC (@SQL)
      FETCH cTables INTO @SchemaName, @TableName   -- fetch next
  END
-- 4  
CLOSE cTables
-- 5
DEALLOCATE cTables

DROP TABLE #Tables

RETURN 

go -----------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditDrop'
go

CREATE PROC pAutoAuditDrop (
	@SchemaName sysname  = 'dbo',
	@TableName sysname,
	@DropBaseTableDDLColumns bit = 1, --0 = don't drop Base Table DDL Columns, 1 = drop  Base Table DDL Columns
	@DropBaseTableTriggers bit = 1, --0 = don't drop audit triggers on tables, 1 = drop audit triggers on tables
									--if @DropBaseTableDDLColumns = 1 then @DropBaseTableTriggers and
									--@DropBaseTableViews default to 1
	@DropBaseTableViews bit=1	--0 = don't drop BaseTable views, 1 = drop BaseTable views
	) 
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to remove AutoAudit triggers for the specified table.

SET NoCount ON

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50),
		@ViewSchema VARCHAR(50),
		@CreatedColumnName sysname,
		@CreatedByColumnName sysname,
		@ModifiedColumnName sysname,
		@ModifiedByColumnName sysname,
		@RowVersionColumnName sysname,
		@ViewPrefix varchar(10),
		@UDFPrefix varchar(10),
		@RowHistoryViewSuffix varchar(20),
		@DeletedViewSuffix varchar(20),
		@RowHistoryFunctionSuffix varchar(20),
		@TableRecoveryFunctionSuffix varchar(20)

SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'
SELECT @ViewSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'Schema for _RowHistory and _Deleted objects'
If @ViewSchema = '<TableSchema>' Set @ViewSchema = @SchemaName

SELECT @ViewPrefix = isnull(ltrim(rtrim([SettingValue])),'v') from [AuditSettings] where [SettingName] = 'ViewPrefix'
SELECT @UDFPrefix = isnull(ltrim(rtrim([SettingValue])),'') from [AuditSettings] where [SettingName] = 'UDFPrefix'
SELECT @RowHistoryViewSuffix = isnull(ltrim(rtrim([SettingValue])),'_RowHistory') from [AuditSettings] where [SettingName] = 'RowHistoryViewSuffix'
SELECT @DeletedViewSuffix = isnull(ltrim(rtrim([SettingValue])),'_Deleted') from [AuditSettings] where [SettingName] = 'DeletedViewSuffix'
SELECT @RowHistoryFunctionSuffix = isnull(ltrim(rtrim([SettingValue])),'_RowHistory') from [AuditSettings] where [SettingName] = 'RowHistoryFunctionSuffix'
SELECT @TableRecoveryFunctionSuffix = isnull(ltrim(rtrim([SettingValue])),'_TableRecovery') from [AuditSettings] where [SettingName] = 'TableRecoveryFunctionSuffix'

SELECT @CreatedColumnName = isnull((SELECT [SettingValue] from [AuditSettings] where [SettingName] = 'CreatedColumnName'),'Created')
SELECT @CreatedByColumnName = isnull((SELECT [SettingValue] from [AuditSettings] where [SettingName] = 'CreatedByColumnName'),'CreatedBy')
SELECT @ModifiedColumnName = isnull((SELECT [SettingValue] from [AuditSettings] where [SettingName] = 'ModifiedColumnName'),'Modified')
SELECT @ModifiedByColumnName = isnull((SELECT [SettingValue] from [AuditSettings] where [SettingName] = 'ModifiedByColumnName'),'ModifiedBy')
SELECT @RowVersionColumnName = isnull((SELECT [SettingValue] from [AuditSettings] where [SettingName] = 'RowVersionColumnName'),'RowVersion')

DECLARE @SQL NVARCHAR(max)

--validate flags
If @DropBaseTableDDLColumns = 1
	Select	@DropBaseTableTriggers = 1,
			@DropBaseTableViews = 1

Print 'Dropping AutoAudit components from table: ' + quotename(@SchemaName) + '.' + quotename(@TableName)
IF @DropBaseTableDDLColumns = 1
	BEGIN
		set context_info 0x1;

		Print '	Dropping Table Audit DDL'
		-- drop default constraints
		If Exists (select * 
					 from sys.objects o 
					   join sys.schemas s on o.schema_id = s.schema_id   
					 where o.name = @TableName + '_' + @CreatedColumnName + '_df'  --no quotename here
					   and s.name = @SchemaName)
		  BEGIN 
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' drop constraint ' + quotename(@TableName + '_' + @CreatedColumnName + '_df')
			EXEC (@SQL)
		  END

		If Exists (select * 
					 from sys.objects o 
					   join sys.schemas s on o.schema_id = s.schema_id   
					 where o.name = @TableName + '_' + @CreatedByColumnName + '_df'  --no quotename here
					   and s.name = @SchemaName)
		  BEGIN 
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' drop constraint ' + quotename(@TableName + '_' + @CreatedByColumnName + '_df')
			EXEC (@SQL)
		  END

		If Exists (select * 
					 from sys.objects o 
					   join sys.schemas s on o.schema_id = s.schema_id   
					 where o.name = @TableName + '_' + @ModifiedColumnName + '_df' --no quotename here
					   and s.name = @SchemaName)
		  BEGIN 
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' drop constraint ' + quotename(@TableName + '_' + @ModifiedColumnName + '_df')
			EXEC (@SQL)
		  END

		If Exists (select * 
					 from sys.objects o 
					   join sys.schemas s on o.schema_id = s.schema_id   
					 where o.name = @TableName + '_' + @ModifiedByColumnName + '_df'  --no quotename here
					   and s.name = @SchemaName)
		  BEGIN 
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' drop constraint ' + quotename(@TableName + '_' + @ModifiedByColumnName + '_df')
			EXEC (@SQL)
		  END

		If Exists (select * 
					 from sys.objects o 
					   join sys.schemas s on o.schema_id = s.schema_id   
					 where o.name = @TableName + '_' + @RowVersionColumnName + '_df'  --no quotename here
					   and s.name = @SchemaName)
		  BEGIN 
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' drop constraint ' + quotename(@TableName + '_' + @RowVersionColumnName + '_df')
			EXEC (@SQL)
		  END

		-- drop Created column 
		IF exists (select *
					  from sys.tables t
						join sys.schemas s
						  on s.schema_id = t.schema_id
						join sys.columns c
						  on t.object_id = c.object_id
					  where  t.name = @TableName AND s.name = @SchemaName and c.name = @CreatedColumnName)
		  BEGIN
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' DROP COLUMN ' + @CreatedColumnName
			EXEC (@SQL)
		  END

		-- drop CreatedBy column 
		IF exists (select *
					  from sys.tables t
						join sys.schemas s
						  on s.schema_id = t.schema_id
						join sys.columns c
						  on t.object_id = c.object_id
					  where  t.name = @TableName AND s.name = @SchemaName and c.name = @CreatedByColumnName)
		  BEGIN
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' DROP COLUMN ' + @CreatedByColumnName
			EXEC (@SQL)
		  END

		-- drop Modified column 
		IF exists( select *
					  from sys.tables t
						join sys.schemas s
						  on s.schema_id = t.schema_id
						join sys.columns c
						  on t.object_id = c.object_id
					  where  t.name = @TableName AND s.name = @SchemaName and c.name = @ModifiedColumnName)
		  BEGIN   
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' DROP COLUMN ' + @ModifiedColumnName
			EXEC (@SQL)
		  END

		-- drop ModifiedBy column 
		IF exists( select *
					  from sys.tables t
						join sys.schemas s
						  on s.schema_id = t.schema_id
						join sys.columns c
						  on t.object_id = c.object_id
					  where  t.name = @TableName AND s.name = @SchemaName and c.name = @ModifiedByColumnName)
		  BEGIN   
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' DROP COLUMN ' + @ModifiedByColumnName
			EXEC (@SQL)
		  END

		-- drop RowVersion column 
		IF exists( select *
					  from sys.tables t
						join sys.schemas s
						  on s.schema_id = t.schema_id
						join sys.columns c
						  on t.object_id = c.object_id
					  where  t.name = @TableName AND s.name = @SchemaName and c.name = @RowVersionColumnName)
		  BEGIN   
			SET @SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' DROP COLUMN ' + @RowVersionColumnName + ''
			EXEC (@SQL)
		  END

	--reset the context info to stop bypassing ddl trigger
	Set context_info 0x0;

	END --IF @DropBaseTableDDLColumns = 1

IF @DropBaseTableTriggers = 1
	BEGIN
		Print '	Dropping Table Audit Triggers'
		-- drop existing insert trigger
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @SchemaName + ''''
			   + '   and o.name = ''' + @TableName + '_Audit_Insert' + ''' )'
			   + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Insert')
		EXEC (@SQL)

		-- drop existing update trigger
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @SchemaName + ''''
			   + '   and o.name = ''' + @TableName + '_Audit_Update' + ''' )'
			   + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Update')
		EXEC (@SQL)

		-- drop existing delete trigger
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @SchemaName + ''''
			   + '   and o.name = ''' + @TableName + '_Audit_Delete' + ''' )'
			   + ' DROP TRIGGER ' + quotename(@SchemaName) + '.' + quotename(@TableName + '_Audit_Delete')
		EXEC (@SQL)

		--Delete table's entry from the AuditBasetables table
		SET @SQL = 'DELETE from ' + quotename(@AuditSchema) + '.AuditBaseTables '
			   + ' where SchemaName = ''' + @SchemaName + ''''
			   + '   and TableName = ''' + @TableName + ''''
		EXEC (@SQL)
	END

IF @DropBaseTableViews = 1
	BEGIN
		Print '	Dropping Table Audit Views'
		-- drop existing _Deleted view
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @ViewSchema + ''''
			   + '   and o.name = ''' + @ViewPrefix + @TableName + @DeletedViewSuffix + ''' )'
			   + ' DROP VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @DeletedViewSuffix)
		EXEC (@SQL)

		-- drop existing _RowHistory view
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @ViewSchema + ''''
			   + '   and o.name = ''' + @ViewPrefix + @TableName + @RowHistoryViewSuffix + ''' )'
			   + ' DROP VIEW ' + quotename(@ViewSchema) + '.' + quotename(@ViewPrefix + @TableName + @RowHistoryViewSuffix)
		EXEC (@SQL)

		-- drop existing _RowHistory UDF
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @ViewSchema + ''''
			   + '   and o.name = ''' + @UDFPrefix + @TableName + @RowHistoryFunctionSuffix + ''' )'
			   + ' DROP FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @RowHistoryFunctionSuffix)
		EXEC (@SQL)

		-- drop existing _TableRecovery UDF
		SET @SQL = 'If EXISTS (Select * from sys.objects o join sys.schemas s on o.schema_id = s.schema_id  '
			   + ' where s.name = ''' + @ViewSchema + ''''
			   + '   and o.name = ''' + @UDFPrefix + @TableName + @TableRecoveryFunctionSuffix + ''' )'
			   + ' DROP FUNCTION ' + quotename(@ViewSchema) + '.' + quotename(@UDFPrefix + @TableName + @TableRecoveryFunctionSuffix)
		EXEC (@SQL)
	END

print ''

go -----------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditAll'
go

CREATE 
PROC [pAutoAuditAll] (
   @StrictUserContext BIT = 1,  -- 2.00 if 0 then permits DML setting of Created, CreatedBy, Modified, ModifiedBy
   @LogSQL BIT = 0,
   @BaseTableDDL BIT = 0,	-- 0 = don't add audit columns to base table, 1 = add audit columns to base table
   @LogInsert TINYINT = 2,	-- 0 = nothing, 1 = header only, 2 = header and detail
   @LogUpdate TINYINT = 2,	-- 0 = nothing, 1 = header only, 2 = header and detail
   @LogDelete TINYINT = 2	-- 0 = nothing, 1 = header only, 2 = header and detail
) 
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to create AutoAudit triggers for all tables in the current database 
-- except for system tables, AutoAudit tables and the tables listed in the AuditAllExclusions table.

SET NoCount ON 

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50)
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'

DECLARE 
   @TableName sysname, 
   @SchemaName sysname, 
   @SQL NVARCHAR(max)
-- for each table
-- 1
DECLARE cTables CURSOR FAST_FORWARD READ_ONLY
  FOR  SELECT s.name, t.name 
			  from sys.tables t
				join sys.schemas s
				  on t.schema_id = s.schema_id
			 where t.name not in 
				('AuditHeader','AuditDetail',
				'SchemaAudit','Audit',
				'AuditHeaderArchive','AuditDetailArchive',
				'LegacyAudit_Migrated','RolePermissions','sysdiagrams')
			 and t.name not like 'aspnet_%'
		AND s.name not in
            (SELECT SchemaName
            FROM    AuditAllExclusions where TableName = '<All>')
        EXCEPT
		SELECT	SchemaName, TableName
		FROM	AuditAllExclusions

--2 
OPEN cTables
--3 
FETCH cTables INTO @SchemaName, @TableName   -- prime the cursor
WHILE @@Fetch_Status = 0 
  BEGIN
		SET @SQL = 'EXEC ' + quotename(@AuditSchema) + '.pAutoAudit ''' + @SchemaName + ''', ''' + @TableName + ''''
		SELECT @SQL = @SQL + ', @StrictUserContext = ' + isnull(cast(@StrictUserContext as varchar(10)),'null')
		SELECT @SQL = @SQL + ', @LogSQL = ' + isnull(cast(@LogSQL as varchar(10)),'null')
		SELECT @SQL = @SQL + ', @BaseTableDDL = ' + isnull(cast(@BaseTableDDL as varchar(10)),'null')
		SELECT @SQL = @SQL + ', @LogInsert = ' + isnull(cast(@LogInsert as varchar(10)),'null')
		SELECT @SQL = @SQL + ', @LogUpdate = ' + isnull(cast(@LogUpdate as varchar(10)),'null')
		SELECT @SQL = @SQL + ', @LogDelete = ' + isnull(cast(@LogDelete as varchar(10)),'null')

		EXEC (@SQL)
      FETCH cTables INTO @SchemaName, @TableName   -- fetch next
  END
-- 4  
CLOSE cTables
-- 5
DEALLOCATE cTables

RETURN 

go --------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditSetTriggerState'
go
Create PROC [pAutoAuditSetTriggerState] 
	(
	@SchemaName sysname = 'dbo',  --this is the default schema name for the tables getting AutoAudit added
	@TableName sysname,
	@InsertEnabledFlag BIT = 1,	-- State for Insert Trigger: 1 = enabled, 0 = disabled
	@UpdateEnabledFlag BIT = 1,	-- State for Update Trigger: 1 = enabled, 0 = disabled
	@DeleteEnabledFlag BIT = 1	-- State for Delete Trigger: 1 = enabled, 0 = disabled
	) with recompile

AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to enable/disable AutoAudit triggers at the SQL Server level for the specified table.

SET NoCount ON
 
DECLARE @SQL NVARCHAR(max),
		@AuditSchema VARCHAR(50),
		@AutopAutoAuditRebuildCurrentSetting varchar(100)

--get @AuditSchema 
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'

--get [AuditSettings] - Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag
Select	@SQL = 'SELECT @SettingValue = [SettingValue] from ' + quotename(@AuditSchema) + '.[AuditSettings] where [SettingName] = ''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag'''
EXEC sp_executesql @SQL, N'@SettingValue varchar(100) OUTPUT', @AutopAutoAuditRebuildCurrentSetting OUTPUT

--disable auto trigger rebuild on schema changes
--set [AuditSettings] = 0 - Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag
If @AutopAutoAuditRebuildCurrentSetting = 1
	BEGIN
		Select	@SQL = 'Update ' + quotename(@AuditSchema) + '.[AuditSettings] Set [SettingValue] = 0 where [SettingName] = ''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag'''
		EXEC (@SQL)
	END

--Set the Insert Trigger as requested
Select	@SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) 
	+ Case when @InsertEnabledFlag = 1 then ' ENABLE TRIGGER ' else ' DISABLE TRIGGER ' END
	+ '[' + @TableName + '_Audit_Insert]'
EXEC (@SQL)

--Set the Update Trigger as requested
Select	@SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) 
	+ Case when @UpdateEnabledFlag = 1 then ' ENABLE TRIGGER ' else ' DISABLE TRIGGER ' END
	+ '[' + @TableName + '_Audit_Update]'
EXEC (@SQL)

--Set the Delete Trigger as requested
Select	@SQL = 'ALTER TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName) 
	+ Case when @DeleteEnabledFlag = 1 then ' ENABLE TRIGGER ' else ' DISABLE TRIGGER ' END
	+ '[' + @TableName + '_Audit_Delete]'
EXEC (@SQL)

--reset auto trigger rebuild on schema changes
--set [AuditSettings] = 1 - Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag
If @AutopAutoAuditRebuildCurrentSetting = 1
	BEGIN
		Select	@SQL = 'Update ' + quotename(@AuditSchema) + '.[AuditSettings] Set [SettingValue] = 1 where [SettingName] = ''Launch pAutoAuditRebuild from SchemaAuditDDLTrigger Enabled Flag'''
print (@SQL)
		EXEC (@SQL)
	END

go --------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditSetTriggerStateAll'
go

CREATE PROC [pAutoAuditSetTriggerStateAll] 
	(
	@InsertEnabledFlag BIT = 1,	-- State for Insert Trigger: 1 = enabled, 0 = disabled
	@UpdateEnabledFlag BIT = 1,	-- State for Update Trigger: 1 = enabled, 0 = disabled
	@DeleteEnabledFlag BIT = 1	-- State for Delete Trigger: 1 = enabled, 0 = disabled
	)
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to enable/disable AutoAudit triggers at the SQL Server level for all tables that are setup with AutoAudit.

SET NoCount ON 

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50)
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'

DECLARE 
   @TableName sysname, 
   @SchemaName sysname, 
   @SQL NVARCHAR(max)

--save the list or tables to a temp table to prevent a cursor issue
SELECT	SchemaName, TableName
INTO	#Tables
FROM	AuditBaseTables
EXCEPT
SELECT	SchemaName, TableName
FROM	AuditAllExclusions

-- for each table
-- 1
DECLARE cTables CURSOR FAST_FORWARD READ_ONLY
  FOR  SELECT SchemaName, TableName 
			  from #Tables
       INTERSECT
       SELECT Schema_Name([schema_id]), [name] as TableName
       FROM sys.objects where type = 'U'
--2 
OPEN cTables
--3 
FETCH cTables INTO @SchemaName, @TableName   -- prime the cursor
WHILE @@Fetch_Status = 0 
  BEGIN
		SET @SQL = 'EXEC ' + quotename(@AuditSchema) + '.pAutoAuditSetTriggerState ''' + @SchemaName + ''', ''' + @TableName + ''', '
			+ cast(@InsertEnabledFlag as varchar(1)) + ', '
			+ cast(@UpdateEnabledFlag as varchar(1)) + ', '
			+ cast(@DeleteEnabledFlag as varchar(1)) + ';'
		EXEC (@SQL)
      FETCH cTables INTO @SchemaName, @TableName   -- fetch next
  END
-- 4  
CLOSE cTables
-- 5
DEALLOCATE cTables

DROP TABLE #Tables

RETURN 

go -----------------------------------------------------------------------

Print 'Creating Stored Procedure - pAutoAuditDropAll'
go
CREATE PROC [pAutoAuditDropAll] 
   (
	@DropAuditTables bit=0,				--0 = don't drop audit tables, 1 = drop audit tables
										-- if @DropAuditTables=1 then @DropAuditViews,@DropBaseTableTriggers,
										-- @DropAuditSPs and @DropAuditDDLTriggers defaults to 1
	@DropAuditViews bit=0,				--0 = don't drop audit views, 1 = drop audit views
	@DropAuditSPs bit = 0,				--0 = don't drop audit SP's, 1 = drop audit SP's
	@DropAuditDDLTriggers bit = 0,		--0 = don't drop audit database DDL trigger, 1 = drop audit database DDL trigger
	@DropBaseTableDDLColumns bit = 0,	--0 = don't drop Base Table DDL Columns, 1 = drop  Base Table DDL Columns
	@DropBaseTableTriggers bit = 0,		--0 = don't drop audit triggers on tables, 1 = drop audit triggers on tables
	@DropBaseTableViews bit=0,			--0 = don't drop BaseTable views, 1 = drop BaseTable views
	@ConfirmAllDrop varchar(10) = 'no'	--Set to 'yes' to proceed
   )
AS 

-- Created for AutoAudit Version 3.30a
-- created by Paul Nielsen and John Sigouin
-- www.SQLServerBible.com
-- AutoAudit.codeplex.com
-- This SP is used to remove AutoAudit triggers for the all tables that are setup with AutoAudit.

If	@DropAuditTables = 0 and 
	@DropAuditViews = 0 and 
	@DropAuditSPs = 0 and 
	@DropAuditDDLTriggers = 0 and 
	@DropBaseTableDDLColumns = 0 and 
	@DropBaseTableTriggers = 0 and 
	@DropBaseTableViews = 0
		Begin
			Raiserror ('You MUST set the input parameters to identify which components of AutoAudit you want to drop.
	@DropAuditTables bit=0,				0 = don''t drop audit tables, 1 = drop audit tables
										    if @DropAuditTables=1 then @DropAuditViews,@DropBaseTableTriggers,
										       @DropAuditSPs and @DropAuditDDLTriggers default to 1
	@DropAuditViews bit=0,				0 = don''t drop audit views, 1 = drop audit views
	@DropAuditSPs bit = 0,				0 = don''t drop audit SP''s, 1 = drop audit SP''s
	@DropAuditDDLTriggers bit = 0,		0 = don''t drop audit database DDL trigger, 1 = drop audit database DDL trigger
	@DropBaseTableDDLColumns bit = 0,	0 = don''t drop Base Table DDL Columns, 1 = drop  Base Table DDL Columns
	@DropBaseTableTriggers bit = 0,		0 = don''t drop audit triggers on tables, 1 = drop audit triggers on tables
	@DropBaseTableViews bit=0,			0 = don''t drop BaseTable views, 1 = drop BaseTable views
	@ConfirmAllDrop varchar(10) = ''no''	Set to ''yes'' to proceed',16,0)
			return
		End
	
If LOWER(isnull(@ConfirmAllDrop, 'no')) <> 'yes'
	begin
			Raiserror ('Executing this SP completely removes some or all AutoAudit components from this database including the AutoAudit added DDL columns from the base tables.
If you are sure you want to do this, re-run the SP with parameter @ConfirmAllDrop = ''yes''.',16,0)
			return
	end

SET NoCount ON 

--get [AuditSettings] 
DECLARE @AuditSchema VARCHAR(50)
SELECT @AuditSchema = [SettingValue] from [AuditSettings] where [SettingName] = 'AuditSchema'

DECLARE 
   @TableName sysname, 
   @SchemaName sysname, 
   @SQL NVARCHAR(max)
   
--validate flags
If @DropAuditTables = 1
	SELECT	@DropAuditViews = 1,
			@DropAuditSPs = 1,
			@DropAuditDDLTriggers = 1,
			@DropBaseTableTriggers = 1,
			@DropBaseTableViews = 1

If @DropBaseTableDDLColumns = 1
	SELECT	@DropBaseTableTriggers = 1,
			@DropBaseTableViews = 1
	
-- remove Schema DDL trigger 
IF @DropAuditDDLTriggers = 1
	BEGIN
		Print 'Dropping SchemaAuditDDLTrigger'
		IF Exists(select * from sys.triggers where name = 'SchemaAuditDDLTrigger')
		  DROP TRIGGER SchemaAuditDDLTrigger ON Database
	END

-- remove AutoAudit SP
IF @DropAuditSPs = 1
	BEGIN
		Print 'Dropping Audit SP''s'

		-- remove pAutoAudit SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAudit'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAudit'
		EXEC(@SQL)

		-- remove pAutoAuditAll SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditAll'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditAll'
		EXEC(@SQL)

		-- remove pAutoAuditRebuild SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditRebuild'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditRebuild'
		EXEC(@SQL)

		-- remove pAutoAuditRebuildAll SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditRebuildAll'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditRebuildAll'
		EXEC(@SQL)

		-- remove pAutoAuditSetTriggerState SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditSetTriggerState'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditSetTriggerState'
		EXEC(@SQL)

		-- remove pAutoAuditSetTriggerStateAll SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditSetTriggerStateAll'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditSetTriggerStateAll'
		EXEC(@SQL)

		-- remove pAutoAuditArchive SP
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditArchive'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditArchive'
		EXEC(@SQL)
	END

-- remove Audit views
IF @DropAuditViews = 1
	BEGIN
		Print 'Dropping vAudit View'
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.vAudit'') IS NOT NULL
		  DROP VIEW ' + quotename(@AuditSchema) + '.vAudit'
		EXEC(@SQL)

		Print 'Dropping vAuditAll View'
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.vAuditAll'') IS NOT NULL
		  DROP VIEW ' + quotename(@AuditSchema) + '.vAuditAll'
		EXEC(@SQL)

		Print 'Dropping vAuditArchive View'
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.vAuditArchive'') IS NOT NULL
		  DROP VIEW ' + quotename(@AuditSchema) + '.vAuditArchive'
		EXEC(@SQL)

		Print 'Dropping vAuditHeaderAll View'
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.vAuditHeaderAll'') IS NOT NULL
		  DROP VIEW ' + quotename(@AuditSchema) + '.vAuditHeaderAll'
		EXEC(@SQL)

		Print 'Dropping vAuditDetailAll View'
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.vAuditDetailAll'') IS NOT NULL
		  DROP VIEW ' + quotename(@AuditSchema) + '.vAuditDetailAll'
		EXEC(@SQL)

	END

IF @DropAuditTables = 1
	BEGIN
		Print 'Dropping Audit Tables'

		-- remove SchemaAudit Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.SchemaAudit'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.SchemaAudit'
		EXEC(@SQL)

		-- remove AuditDetail Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.AuditDetail'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.AuditDetail'
		EXEC(@SQL)

		-- remove AuditHeader Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.AuditHeader'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.AuditHeader'
		EXEC(@SQL)

		-- remove AuditAllExclusions Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.AuditAllExclusions'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.AuditAllExclusions'
		EXEC(@SQL)

		-- remove AuditDetailArchive Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.AuditDetailArchive'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.AuditDetailArchive'
		EXEC(@SQL)

		-- remove AuditHeaderArchive Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.AuditHeaderArchive'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.AuditHeaderArchive'
		EXEC(@SQL)

	END

-- for each table
DECLARE cTables CURSOR FAST_FORWARD READ_ONLY
  FOR  SELECT s.name, t.name 
			  from sys.tables t
				join sys.schemas s
				  on t.schema_id = s.schema_id
			 where t.name not in ('AuditHeader','AuditDetail','SchemaAudit'
									,'LegacyAudit_Migrated','LegacySchemaAudit_Migrated')

OPEN cTables

FETCH cTables INTO @SchemaName, @TableName   -- prime the cursor
WHILE @@Fetch_Status = 0 
  BEGIN
		SET @SQL = 'EXEC ' + quotename(@AuditSchema) + '.pAutoAuditDrop @SchemaName=''' + @SchemaName + '''' +
					', @TableName=''' + @TableName + '''' +
					', @DropBaseTableDDLColumns=' + cast(@DropBaseTableDDLColumns as varchar) + 
					', @DropBaseTableTriggers=' + cast(@DropBaseTableTriggers as varchar) + 
					', @DropBaseTableViews=' + cast(@DropBaseTableViews as varchar)

		EXEC (@SQL)
      FETCH cTables INTO @SchemaName, @TableName   -- fetch next
  END
CLOSE cTables
DEALLOCATE cTables

-- remove AutoAudit Tables
IF @DropAuditTables = 1
	BEGIN
		-- remove AuditSettings Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.[AuditSettings]'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.[AuditSettings]'
		EXEC(@SQL)

		-- remove AuditBaseTables Table
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.[AuditBaseTables]'') IS NOT NULL
		  DROP TABLE ' + quotename(@AuditSchema) + '.[AuditBaseTables]'
		EXEC(@SQL)
	END

-- remove pAutoAuditDrop SP
IF @DropAuditSPs = 1
	BEGIN
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditDrop'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditDrop'
		EXEC(@SQL)
	END

-- remove pAutoAuditDropAll SP
IF @DropAuditSPs = 1
	BEGIN
		SET @SQL = 'IF Object_id(''' + quotename(@AuditSchema) + '.pAutoAuditDropAll'') IS NOT NULL
		  DROP PROC ' + quotename(@AuditSchema) + '.pAutoAuditDropAll'
		EXEC(@SQL)
	END
go

--**************** Setup Script Section #9 ****************
-- Assign desired schema to newly created stored procedures
--*********************************************************
--change the schema for the Audit sp's to the <audit> schema
declare @AuditSchema VARCHAR(50)
declare @SQL varchar(max)
SELECT @AuditSchema = [SettingValue] from #Settings where [SettingName] = 'AuditSchema'

SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAudit'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditAll'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditDrop'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditDropAll'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditRebuild'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditRebuildAll'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditSetTriggerState'
EXEC (@SQL)
SET @SQL = 'ALTER SCHEMA ' + quotename(@AuditSchema) + ' TRANSFER dbo.pAutoAuditSetTriggerStateAll'
EXEC (@SQL)


--**************** Setup Script Section #10 ****************
-- Add QUOTENAME delimiters to TableName column in AuditHeader
--**********************************************************
print '' --blank line
raiserror ('Adding QUOTENAME delimiters to TableName column in AuditHeader',0,0) with nowait
SET @SQL = 'Update ' + quotename(@AuditSchema) + '.AuditHeader
set		TableName = QUOTENAME(left(TableName,PatIndex(''%.%'',TableName)-1)) + ''.'' + 
					QUOTENAME(substring(TableName,PatIndex(''%.%'',TableName)+1,1000))
where	TableName like ''[^[]%.%'''
EXEC (@SQL)
raiserror ('Adding QUOTENAME delimiters to TableName column in AuditHeaderArchive',0,0) with nowait
SET @SQL = 'Update ' + quotename(@AuditSchema) + '.AuditHeaderArchive
set		TableName = QUOTENAME(left(TableName,PatIndex(''%.%'',TableName)-1)) + ''.'' + 
					QUOTENAME(substring(TableName,PatIndex(''%.%'',TableName)+1,1000))
where	TableName like ''[^[]%.%'''
EXEC (@SQL)

print '' --blank line


--**************** Setup Script Section #11 ****************
-- rebuild all existing AutoAudit Triggers
--**********************************************************
DECLARE @RebuildTriggersAfterInstall bit	
SELECT @RebuildTriggersAfterInstall = [SettingValue] from #Settings where [SettingName] = 'RebuildTriggersAfterInstall'
If @RebuildTriggersAfterInstall = 1
	begin
		SET @SQL = quotename(@AuditSchema) + '.pAutoAuditRebuildAll'
		EXEC (@SQL)
	end
Else
	begin
		Print '*** Execute pAutoAuditRebuild or pAutoAuditRebuildAll to upgrade AutoAudit triggers and views. ***'
	end

--Drop the #Settings temp table
begin try
	drop table #Settings
end try
begin catch
end catch

--re-enable execution if required
set noexec off

--use tempdb
