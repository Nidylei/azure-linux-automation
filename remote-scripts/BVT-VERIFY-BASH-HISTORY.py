#! /usr/bin/env python
from azuremodules import *
import os
import os.path

root_bash_hist_file = '/root/.bash_history'
root_bash_hist_file_default = '/root/default_bash_history'

def RunTest():
	UpdateState("TestRunning")
	if os.path.exists(root_bash_hist_file_default):
		RunLog.info("This is a prepared image, check the copied default history file: %s" % root_bash_hist_file_default)
		result = IsBashHistFileEmpty(root_bash_hist_file_default)
	elif os.path.exists(root_bash_hist_file):
		RunLog.info("This is a unprepared image, check the original history file: %s" % root_bash_hist_file)
		result = IsBashHistFileEmpty(root_bash_hist_file)
	else:
		RunLog.info("No bash history file exists.")
		result = True

	if result:
		ResultLog.info('PASS')
		RunLog.info("Empty, as expected.")
	else:
		ResultLog.error('FAIL')
		RunLog.error("Not empty, non-expected.")
	UpdateState("TestCompleted")

def IsBashHistFileEmpty(file):
	return os.stat(file).st_size == 0

RunTest()
