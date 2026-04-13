% Wrapper script to run parameter c optimization test
% This script adds necessary paths and calls the test

% Add paths
addpath(genpath('src'));
addpath('config');

% Run the test
test_parameter_c_optimization();
