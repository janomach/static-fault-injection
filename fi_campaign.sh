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
gpr_size=5036   # 64*(15.180 + 63.375)
rfc_size=4083   # m_rfc - gpr_size
pred_size=4775  # ras + pred
alu_size=1924   #
mdu_size=3511   #
dp_size=5118    # fe + id + op - pred_size
tp_size=6383    # core - other_groups - m_csru

gpr_file=$analysis_dir/source/$system_config/gpr_instances.txt
rfc_file=$analysis_dir/source/$system_config/rfc_instances.txt
pred_file=$analysis_dir/source/$system_config/pred_instances.txt
alu_file=$analysis_dir/source/$system_config/alu_instances.txt
mdu_file=$analysis_dir/source/$system_config/mdu_instances.txt
dp_file=$analysis_dir/source/$system_config/dp_instances.txt
tp_file=$analysis_dir/source/$system_config/tp_instances.txt

# Script settings - preserve variables, change their values #######################################
# Group settings
group_names=("gpr" "rfc" "pred" "alu" "mdu" "dp" "tp")           # Fault injection group names
group_enable=(1 1 1 1 1 1 1)                                     # Select which group is enabled
group_sizes=($gpr_size $rfc_size $pred_size $alu_size $mdu_size $dp_size $tp_size)  # Footprint (Area) of the group at the chip
group_files=($gpr_file $rfc_file $pred_file $alu_file $mdu_file $dp_file $tp_file)  # Group files containing all fault injection targets

# Fault injection parameters
timeout=600000                                                  # time at which the fault injection should stop
fastest=520000                                                  # expected simulation time without fault injection
max_fi_delay=1000                                               # maximum delay between two fault injections / all groups
min_fi_delay=100                                                # minimum delay between two fault injections / all groups
mbu_prob=0                                                      # probability (%) of multi-bit (double-bit) fault
stuck_prob=0                                                    # probability (%) of stack-at fault
clock_period=10                                                 # clock cycle period during RTL simulation
run_reps=100                                                    # number of simulation runs
fi_strategy=1                                                   # 0 - constant period, 1 - random period

# Hook RTL signals for reporting
halt_signal="/tb_mh_wrapper/s_halt"                             # execution is halted - simulation finish
timeout_signal="/tb_mh_wrapper/s_sim_timeout"                   # execution timeout
fail_signal="/tb_mh_wrapper/s_unrec_err[0]"                     # execution failure
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

generate_fault() { #see_cycle #target
    # type of fault (transient or stuck-at)
    get_random
    transient=$((($random_dec % 100) >= $stuck_prob))
    # simulation time at which the fault injection happens
    see_time=$(($1*$clock_period + $clock_period/2))
    # save fault injection command to the TCL script
    echo "$see_time $2 $clock_period $transient" >> $3
}

sort_faults_time() {
  sort -nk1 $1 -o $1
}

prepare_fi_file() {
  while IFS= read -r line; do
    see_time=$(cut -d ' ' -f1 <<< $line)
    see_target=$(cut -d ' ' -f2 <<< $line)
    see_period=$(cut -d ' ' -f3 <<< $line)
    see_transient=$(cut -d ' ' -f4 <<< $line)
    echo "when {\$now == {$see_time ns}} { inject_fault \"$see_target\" $see_period $see_transient}" >> $2
  done < $1
}

generate_faults_cp() { #fi_delay #tcount #tfile
  work_file=$work_dir/work_file.txt
  if test -f $work_file; then
    rm $work_file
  fi
  touch $work_file
  get_random
  # the first fault injection is constrained by the expected (fastest) simulation time
  see_cycle=$((($random_dec % $1) % $fastest))
  # fault generation is constrained by the timeout setting
  while [ $see_cycle -le $timeout ]; do
    # select random target
    get_random
    random_target=$((($random_dec % $2) + 1))
    target=$(sed "$random_target!d" $3)
    generate_fault $see_cycle $target $work_file
    # repeat for MBU
    get_random
    if [ $(($random_dec % 100)) -lt $mbu_prob ]; then
      # select the next target from the tfile
      if [ $random_target -eq $2 ]; then
        random_target=$(($random_target - 1))
      else
        random_target=$(($random_target + 1))
      fi
      target=$(sed "$random_target!d" $3)
      generate_fault $see_cycle $target $work_file
      # to preserve average fault rate, increment twice
      see_cycle=$(($see_cycle + $1))
    fi
    # generate new fault injection clock cycle
    see_cycle=$(($see_cycle + $1))
  done
  prepare_fi_file $work_file $run_file 
}

generate_faults_rp() { #fi_delay #tcount #tfile
  work_file=$work_dir/work_file.txt
  if test -f $work_file; then
    rm $work_file
  fi
  touch $work_file
  total_errors=$(($timeout / $1))
  applied_errors=0
  # fault generation is constrained by the timeout setting
  while [ $applied_errors -lt $total_errors ]; do
    # generate clock cycle
    get_random
    see_cycle=$(($random_dec % $timeout))
    # select random target
    get_random
    random_target=$((($random_dec % $2) + 1))
    target=$(sed "$random_target!d" $3)
    generate_fault $see_cycle $target $work_file
    # repeat for MBU
    get_random
    if [ $(($random_dec % 100)) -lt $mbu_prob ]; then
      # select the next target from the tfile
      if [ $random_target -eq $2 ]; then
        random_target=$(($random_target - 1))
      else
        random_target=$(($random_target + 1))
      fi
      target=$(sed "$random_target!d" $3)
      generate_fault $see_cycle $target $work_file
      # to preserve average fault rate, increment twice
      applied_errors=$(($applied_errors + 1))
    fi
    # increment at the end of the loop
    applied_errors=$(($applied_errors + 1))
  done
  sort_faults_time $work_file
  prepare_fi_file $work_file $run_file 
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
  group_tcount[$i]=$((${group_tcount[$i]} + 1))
  echo "Group ${group_names[$i]} has ${group_tcount[$i]} targets"
  if [ ${group_enable[$i]} -eq 1 ]; then
    total_size=$(($total_size + ${group_sizes[$i]})) 
  fi
done

echo "Fault injection delay: <$min_fi_delay, $max_fi_delay>"
if [ $fi_strategy -eq 0 ]; then
  echo "Fault injection strategy: constant period"
else
  echo "Fault injection strategy: random period"
fi
echo "Multi-bit-upset probability: $mbu_prob%"
echo "Stuck-at fault probability: $stuck_prob%"
echo "Application: $application"

for i in $(seq $run_reps); do
  get_random
  avg_fi_delay=$(($min_fi_delay + ($random_dec % ($max_fi_delay - $min_fi_delay))))
  echo "########################### run $i/$run_reps, FI delay: $avg_fi_delay ###########################"
  echo -n "$i,$avg_fi_delay," >> $result_file
  run_file=$work_dir/run_$i.tcl
  touch $run_file

  # Prepare TCL function in the run file
  echo "proc inject_fault {target clock_period transient} {" >> $run_file
  echo "    set actual_value [ examine -binary \${target} ]" >> $run_file
  echo "    if { \${actual_value} == \"1'b1\" } {" >> $run_file
  echo "        if { \${transient} == \"1\" } {" >> $run_file
  echo "          force \$target 0 -cancel \$clock_period" >> $run_file
  echo "        } else {" >> $run_file
  echo "          force \$target 0" >> $run_file
  echo "        }" >> $run_file
  echo "    } else {" >> $run_file
  echo "        if { \${transient} == \"1\" } {" >> $run_file
  echo "          force \$target 1 -cancel \$clock_period" >> $run_file
  echo "        } else {" >> $run_file
  echo "          force \$target 1" >> $run_file
  echo "        }" >> $run_file
  echo "    }" >> $run_file
  echo "}" >> $run_file

  # Generate fault injection campaign
  for i in "${!group_files[@]}"; do
    if [ ${group_enable[$i]} -eq 1 ]; then
      # generate fault injection delay for selected group - larger groups have smaller fi delay
      group_fi_delay=$((($avg_fi_delay * $total_size) / ${group_sizes[$i]}))
      echo "Group ${group_names[$i]} has FI delay: $group_fi_delay"
      echo "# Group: ${group_names[$i]}" >> $run_file
      if [ $fi_strategy -eq 0 ]; then
        generate_faults_cp $group_fi_delay ${group_tcount[$i]} ${group_files[$i]}
      else
        generate_faults_rp $group_fi_delay ${group_tcount[$i]} ${group_files[$i]}
      fi
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
