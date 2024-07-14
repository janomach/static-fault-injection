#!/usr/bin/bash

#  Copyright 2024 Ján Mach
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

###################################################################################################

# Custom variables - modify as you need ###########################################################
system_config="hardisc"
analysis_dir=$PWD/../analysis
work_dir=$analysis_dir/work
#### hardisc
predictor_size=5343
rfgpr_size=5820
pipe_size=14819
alu_size=6715
#### dcls
#predictor_size=10619
#rfgpr_size=6703
#pipe_size=11315
#alu_size=6680
#### tcls
#predictor_size=16213
#rfgpr_size=10032
#pipe_size=18289
#alu_size=10114

predictor_file=$analysis_dir/source/$system_config/predictor_instances.txt
rfgpr_file=$analysis_dir/source/$system_config/rfgpr_instances.txt
pipe_file=$analysis_dir/source/$system_config/pipe_instances.txt
alu_file=$analysis_dir/source/$system_config/alu_instances.txt

# Script settings - preserve variables, change their values #######################################
# Group settings
group_names=("predictor" "rfgpr" "pipe" "alu")                  # Fault injection group names
group_enable=(1 1 1 1)                                          # Select which group is enabled
group_sizes=($predictor_size $rfgpr_size $pipe_size $alu_size)  # Footprint (Area) of the group at the chip
group_files=($predictor_file $rfgpr_file $pipe_file $alu_file)  # Group files containing all fault injection targets

# Fault injection parameters
timeout=600000                                                  # time at which the fault injection should stop
fastest=504272                                                  # expected simulation time without fault injection
max_fi_delay=10000                                              # maximum delay between two fault injections / all groups
min_fi_delay=1000                                               # minimum delay between two fault injections / all groups
clock_period=10                                                 # clock cycle period during RTL simulation
run_reps=100                                                    # number of simulation runs

# Hook RTL signals for reporting
halt_signal="/tb_mh_wrapper/s_halt"                             # execution is halted - simulation finish
timeout_signal="/tb_mh_wrapper/s_sim_timeout"                   # execution timeout
fail_signal="/tb_mh_wrapper/s_hrdmax_rst"                       # execution failure
app_result="/tb_mh_wrapper/s_d_hwdata[0]"                       # application result

# Fault injection application
application=$1

# Results report file
result_file=$work_dir/core_report.txt

# Functions #######################################################################################

run_simulation() {
  # customizable simulation command
  vsim -c -quiet -voptargs=+acc ../sim/work.tb_mh_wrapper -do "source $1" -do "source $analysis_dir/report_result.tcl" +TIMEOUT=$timeout +BIN=$application +LOGGING=0 +SEE_PROB=0 +SEE_GROUP=0 +LAT=0
}

get_random() {
  random_hex=$(openssl rand -hex 4)
  random_dec=$(echo $((16#$random_hex)))
}

generate_faults() { #fi_delay #tcount #tfile
  get_random
  # the first fault injection is constrained by the expected (fastest) simulation time
  see_cycle=$((($random_dec % $1) % $fastest))
  # fault generation is constrained by the timeout setting
  while [ $see_cycle -le $timeout ]; do
    # select random target
    get_random
    random_target=$((($random_dec % $2) + 1))
    target=$(sed "$random_target!d" $3)
    # simulation time at which the fault injection happens
    see_time=$(($see_cycle*$clock_period + $clock_period/2))
    # save fault injection command to the TCL script
    echo "when {\$now == {$see_time ns}} { inject_fault \"$target\" $clock_period }" >> $run_file
    # generate new fault injection clock cycle
    see_cycle=$(($see_cycle + $1))
  done
}

###################################################################################################

rm -r $work_dir
mkdir $work_dir
touch $result_file
random_dec=0
total_size=0

# get number of targets
for i in "${!group_files[@]}"; do
  group_tcount[$i]=$(wc -l < ${group_files[$i]})
  echo "${group_names[$i]} targets: ${group_tcount[$i]}"
  total_size=$(($total_size + ${group_sizes[$i]})) 
done

echo "Fault injection application: $application"

for i in $(seq $run_reps); do
  get_random
  avg_fi_delay=$(($min_fi_delay + ($random_dec % ($max_fi_delay - $min_fi_delay))))
  echo "########################### run $i, fault injection delay: $avg_fi_delay ###########################"
  echo -n "$i,$avg_fi_delay," >> $result_file
  run_file=$work_dir/run_$i.tcl
  touch $run_file

  # Prepare TCL function in the run file
  echo "proc inject_fault {target clock_period} {" >> $run_file
  echo "    set actual_value [ examine \${target} ]" >> $run_file
  echo "    if { \${actual_value} == \"1'h1\" } {" >> $run_file
  echo "        force \$target 0 -cancel \$clock_period" >> $run_file
  echo "    } else {" >> $run_file
  echo "        force \$target 1 -cancel \$clock_period" >> $run_file
  echo "    }" >> $run_file
  echo "}" >> $run_file

  # Generate fault injection campaign
  for i in "${!group_files[@]}"; do
    if [ ${group_enable[$i]} -eq 1 ]; then
      # generate fault injection delay for selected group - larger groups have smaller fi delay
      group_fi_delay=$((($avg_fi_delay * $total_size) / ${group_sizes[$i]}))
      echo "${group_names[$i]} fault injection delay: $group_fi_delay"
      generate_faults $group_fi_delay ${group_tcount[$i]} ${group_files[$i]}
    fi
  done

  # prepare reporting
  echo "# report settings" >> $run_file
  echo "set clock_period $clock_period" >> $run_file
  echo "set work_dir \"$work_dir\"" >> $run_file
  echo "set halt_signal $halt_signal" >> $run_file
  echo "set timeout_signal $timeout_signal" >> $run_file
  echo "set fail_signal $fail_signal" >> $run_file
  echo "set app_result $app_result" >> $run_file
  cat report_result.tcl >> $run_file

  run_simulation $run_file
done
