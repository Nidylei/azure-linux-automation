#!/usr/bin/env python
from azuremodules import *
import re
import os
current_distro        = "unknown"
distro_version        = "unknown"
pkgcheckcmd           = 'unknown'
pattern               = re.compile(r'unknown')

def RunTest():
    flag = False
    UpdateState("TestRunning")
    if os.path.exists('ntpinfo.log'):
        os.remove('ntpinfo.log')
    [current_distro, distro_version] = DetectDistro()
    vercheckcmd = 'ntpd --version 2>&1'
    if(current_distro == 'unknown'):
        RunLog.error ("unknown distribution found, exiting")
        ResultLog.info('ABORTED')
        exit()
    if(current_distro == "ubuntu" or current_distro == "debian"):
        pkgcheckcmd = 'apt-cache policy ntp'
        pattern = re.compile(r'\s*Candidate: (\S+)\+\S+')
    elif(current_distro == "centos" or current_distro == "rhel" or current_distro == "fedora" or current_distro == "Oracle"):
        pkgcheckcmd = 'yum info ntp'
        pattern = re.compile(r'Version\s*: (\S+)')
    elif(current_distro == "SUSE" or current_distro == "sles" or current_distro == "opensuse"):
        pkgcheckcmd = 'zypper info ntp'
        pattern = re.compile(r'Version: (\S+)')

    output = Run(vercheckcmd)  
    outputlist = re.split("\n", output)
    for line in outputlist:
        match = re.match(r'ntpd (\d\S+)@\d\S+|ntpd (\d\S+)', line)
        if match:
            flag = True
            if match.group(1) is not None:
                ntpVersion = match.group(1)
            if match.group(2) is not None:
                ntpVersion = match.group(2)
            f = file('ntpinfo.log','w+')
            f.write('true:' + ntpVersion)
            f.close()
            RunLog.info('Verified the installed ntp version: ' + ntpVersion)
            break
    if not flag:
        output = Run(pkgcheckcmd)
        outputlist = re.split("\n", output)
        for line in outputlist:
            match = pattern.match(line)
            if match:
                flag = True
                ntpVersion = match.group(1)
                f = file('ntpinfo.log','w+')
                f.write('false:' + ntpVersion)
                f.close()
                RunLog.info('Verified the ntp package version: ' + ntpVersion)
                break
    if flag:
        ResultLog.info('PASS')
    else:
        RunLog.error('Failed to get ntp package or installed ntp version:\n')
        ResultLog.error('FAIL')
    UpdateState("TestCompleted")

RunTest()