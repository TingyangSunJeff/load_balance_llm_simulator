@echo off
echo Starting MATLAB simulation...
matlab -batch "setup_project(); run_example()"
echo MATLAB simulation completed.
pause