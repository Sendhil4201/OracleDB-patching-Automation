#! /bin/ksh
#############################################################################################
# Description             : Applying PSU patching  for RDBMS
# Version                 : ORACLE Version 12c and above
# Created on              : 23-Mar-2021  by Sendhil J
# Last updated            : 23-Mar-2021  by Sendhil J
# Usage                   : Uses oracle opatch utility to apply PSU patches
# Script Parameters       : $1 == DB or OJVM
#############################################################################################
#############################################################################################
# function CheckConflict
# function apply_DB
# function apply_OJVM
############################################################################################

#=====================================================================================
# User vars
#=====================================================================================

if [ $# -lt 2 ];then
  echo " Usage : You MUST specify ./apply_psu_patch.ksh CheckConflict or ApplyDB or ApplyOJVM or Rollback followed by OH And Patchlocation or patchid"
  echo " Usage : example ./apply_psu_patch.ksh CheckConflict OH Patchlocation"
  echo " exiting with return code 255... "
  exit 255
fi

export STAMP="${ORACLE_SID}.$(date +\%y\%m\%d\%H\%M)"
export OH=$2
echo $OH
export PATCH_DIR=$3
echo $PATCH_DIR
#=====================================================================================
# Setting the ORATAB
#=====================================================================================
if [ -f /etc/oratab ]
  then
  ORATAB=/etc/oratab
  export ORATAB
## If OS is Solaris:
elif [ -f /var/opt/oracle/oratab ]
  then
  ORATAB=/var/opt/oracle/oratab
  export ORATAB
fi

#=====================================================================================
# function CheckConflict
#=====================================================================================
function checkconflict
{
echo " ************************************************* "
echo " Checking for database Patch conflict : $OH"
echo " ************************************************* "
#CheckConflictAgainstOHWithDetail of the database
echo $OH
echo $PATCH_DIR
for j in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
echo $j
done
export ORACLE_SID=$j
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
export PATH=$PATH:$ORACLE_HOME/OPatch

cd ${PATCH_DIR} && opatch prereq CheckConflictAgainstOHWithDetail -ph ./
}

#=====================================================================================
# function ApplyDB
#=====================================================================================
function applydb
{
echo " ************************************************* "
echo " Applying PSU database Patch on : $OH"
echo " ************************************************* "
# Stop the Oracle databases: Apply the PSU Patch in silent
echo $OH
echo $PATCH_DIR
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
export PATH=$PATH:$ORACLE_HOME/OPatch

sqlplus "/as sysdba"  << EOF  > $HOME/scripts/applyPSU${STAMP}.log
select name ,open_mode from v\$database;
shutdown immediate;
exit;
EOF

#Stop the Listener
lsnrctl stop $i >> $HOME/scripts/applyPSU${STAMP}.log
done

echo "Shutdown of all DB and Listener completed Successfully "
echo "Apply Patch now"
export PATH=$PATH:$ORACLE_HOME/OPatch
echo "Applying Patch"
cd ${PATCH_DIR} && opatch apply -silent
if [ "$?" != 0 ] ; then
        echo "Error while applying patch"
        exit 1
 fi
echo "Patch Successfully Applied"
echo "Bringing Up all the database and applying datapatch"
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/applyPSU${STAMP}.log
startup
select name ,open_mode from v\$database;
exit;
EOF
#Start the Listener
lsnrctl start $i >> $HOME/scripts/applyPSU${STAMP}.log

echo "Applying datapatch now on all database"
cd ${ORACLE_HOME}/OPatch && ./datapatch -verbose

echo "run utlrp.sql on all database"
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/applyPSU${STAMP}.log
select name ,open_mode from v\$database;
set feedback off
set echo off verify off
set pages 1000
set lines 130
column  comp_name format A30
column  version    format a20
column  status    format a20
set serveroutput on;
spool postpatching.lst
@$ORACLE_HOME/rdbms/admin/utlrp.sql
Select comp_name, version, status from dba_registry;
spool off;
exit;
EOF
done
}

#=====================================================================================
# function ApplyOJVM
#=====================================================================================
function applyojvm
{
echo " ************************************************* "
echo " Applying PSU database Patch on : $OH"
echo " ************************************************* "
# Stop the Oracle databases: Apply the PSU Patch in silent
echo $OH
echo $PATCH_DIR
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
export PATH=$PATH:$ORACLE_HOME/OPatch

sqlplus "/as sysdba"  << EOF  > $HOME/scripts/applyOJVM${STAMP}.log
select name,open_mode,status from v\$database, v\$instance;
shutdown immediate;
exit;
EOF
#Stop the Listener
lsnrctl stop $i >> $HOME/scripts/applyOJVM${STAMP}.log
done

echo "Shutdown of all DB and Listener completed successfully"
echo "Apply Patch now"
export PATH=$PATH:$ORACLE_HOME/OPatch
echo "Applying Patch"
cd ${PATCH_DIR} && opatch apply
if [ "$?" != 0 ] ; then
        echo "Error while Applying Patch"
        exit 1
 fi
echo "Patch Successfully Applied"
echo "Bringing Up all the database and applying datapatch"
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/applyOJVM${STAMP}.log
startup upgrade
select name,open_mode,status from v\$database, v\$instance;
exit;
EOF
echo "Starting the Listener"
#Start the Listener
lsnrctl start $i >> $HOME/scripts/applyOJVM${STAMP}.log

echo "Applying datapatch now on all database"
cd ${ORACLE_HOME}/OPatch && ./datapatch -verbose

#shutdown and startup the database in normal mode And run the utlrp.sql
echo "Starting the database in Normal mode and running utlrp.sql"
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/applyOJVM${STAMP}.log
select name,open_mode,status from v\$database, v\$instance;
shutdown immediate;
startup
select name,open_mode,status from v\$database, v\$instance;
set feedback off
set echo off verify off
set pages 1000
set lines 130
column  comp_name format A30
column  version    format a20
column  status    format a20
set serveroutput on;
spool postpatching.lst
@$ORACLE_HOME/rdbms/admin/utlrp.sql
Select comp_name, version, status from dba_registry;
spool off;
exit;
EOF
done
}

#=====================================================================================
# function rollback
#=====================================================================================
function rollback
{
echo " ************************************************* "
echo " Rollback database Patch on : $OH"
echo " ************************************************* "
# Stop the Oracle databases:
# rollback
echo $OH
echo $PATCH_DIR
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
export PATH=$PATH:$ORACLE_HOME/OPatch
sqlplus "/as sysdba"  << EOF  > $HOME/scripts/rollbackPSU${STAMP}.log
select name ,open_mode from v\$database;
shutdown immediate;
exit;
EOF
#Stop the Listener
lsnrctl stop $i >> $HOME/scripts/rollbackPSU${STAMP}.log
done

echo "Shutdown of all DB and Listener completed"
echo "Rollback Patch now"
export PATH=$PATH:$ORACLE_HOME/OPatch
echo "Rollback the Patch"
cd $ORACLE_HOME/OPatch && opatch rollback -id $PATCH_DIR
if [ "$?" != 0 ] ; then
        echo "Error while performing rollback"
        exit 1
fi
echo "Patch Successfully rolled back"
echo "Bringing Up all the database and applying datapatch"
for i in `cat $ORATAB | grep $OH |grep -v "#" | grep -v "*" | cut -d ':' -f1`
do
export ORACLE_SID=$i
export ORAENV_ASK=NO
. oraenv
echo $ORACLE_SID
echo $ORACLE_HOME
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/rollbackPSU${STAMP}.log
startup
select name,open_mode,status from v\$database, v\$instance;
exit;
EOF
#Start the Listener
lsnrctl start $i >> $HOME/scripts/rollbackPSU${STAMP}.log

echo "Applying datapatch now on all database"
cd ${ORACLE_HOME}/OPatch && ./datapatch -verbose

echo "run utlrp.sql on all database"
sqlplus "/as sysdba"  << EOF  >> $HOME/scripts/rollbackPSU${STAMP}.log
select name,open_mode,status from v\$database, v\$instance;
set feedback off
set echo off verify off
set pages 1000
set lines 130
column  comp_name format A30
column  version    format a20
column  status    format a20
set serveroutput on;
spool postpatching.lst
@$ORACLE_HOME/rdbms/admin/utlrp.sql
Select comp_name, version, status from dba_registry;
spool off;
exit;
EOF
done
echo "Rollback the Patch"
}
#=====================================================================================
# MAIN - Calling the function with the Appropriate type of Patching
# and when completed, returning to the main script with that Return Code.
#=====================================================================================
case $1 in
                "CheckConflict") checkconflict  ;;
                "ApplyDB") applydb  ;;
                "ApplyOJVM") applyojvm ;;
                "Rollback") rollback  ;;
esac
exit ${RC}

