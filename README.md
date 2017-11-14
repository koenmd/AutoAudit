# AutoAudit
Copy of autoaudit.codeplex.com

AutoAudit script
Paul Nielsen, John Sigouin
www.sqlserverbible.com

Version 3.30 is available in the downloads tab.

AutoAudit is a SQL Server (2005, 2008, 2012) Code-Gen utility that creates Audit Trail Triggers with:
Insert - event logged to Audit table
Update - old and new values logged to Audit table
Delete - logs all final values to the Audit table
CreatedDate, CreatedBy, ModifiedDate, ModifiedBy, and RowVersion (incrementing INT) columns optionally added to table
View to reconstruct deleted rows
UDF and view to reconstruct Row History
UDF to recover the data from a table at any point in time - NEW FOR 3.30
Schema Audit Trigger to track schema changes
Re-code-gens triggers when Alter Table changes the table


Version 3.30 major changes:
Added the _TableRecovery UDF that returns the data from a table as it existed at a specified point in time
Added User-configurable prefixes and suffixes for AutoAudit views and UDF's
Added a parameter to configure the date style to either 113 or 121 in AutoAudit tables
Added QUOTENAME delimiters around TableName entry in AuditHeader table
Added LoginName to the SchemaAudit table
Changed the default behaviour of the pAutoAuditDropAll stored procedure to 0 (don't drop) instead of 1 and added a safeguard confirmation parameter.
Added the Comment column to the AuditAllExclusions table

Version 3.20h major changes:
Added an option for pAutoAuditAll to exclude all tables from specified schemas

Version 3.20e major changes:
Handle primary keys with up to 5 columns
implemented Quotename and all over to handle any table and column name
Save changes for a subset of the columns in a table
Schema support so that the Audit tables and objects can be created in any schema (not just dbo)
Added a _RowHistory view for each audited table
Implemented Quotename() all over to ensure AutoAudit works with any table and column name
Adjusted AutoAudit to make it work with case-sensitive database collation
Added the option for users to rename the Created, CreatedBy, Modified, ModifiedBy, RowVersion columns
Added audit data archiving feature

There is close to 80 changes between version 2.00h and 3.30. Please refer to the Documention TAB and setup script file for all the details. I also added information in the guide section to explain the new features in more details.


Version 2 adds:
Optional logging of submitted SQL Batch
Optional Insert logging (none, event, all values)
Optional strict or loose user context logging
Optional base table DDL columns (Created, CreatedBy, Modified, ModifiedBy, and RowVersion)

initial AutoAudit blog post: 
http://sqlblog.com/blogs/paul_nielsen/archive/2007/01/15/codegen-to-create-fixed-audit-trail-triggers.aspx
