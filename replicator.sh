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

# simple script for expanding RTL wires/registers into individual bits
# Example:  string describing an array of 5-bit registers
#           input ->  /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data 2 5
#           output -> /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[0][0]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[0][1]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[0][2]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[0][3]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[0][4]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[1][0]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[1][1]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[1][2]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[1][3]
#                     /tb_mh_wrapper/dut/rep[0]/core/m_rfc/m_acm/m_acm_add/r_data[1][4]
# Usage:  $1 -> input file with strings describing RTL resources
#         $2 -> output file with resources expanded to individual bits

input=$1
rm $2
while read -r line
do
  read -ra ENTRY <<<"$line"
  for (( i=0; i<${ENTRY[1]}; i++ ))
  do
    for (( j=0; j<${ENTRY[2]}; j++ ))
    do
      echo ${ENTRY[0]}"["$i"]["$j"]" >> $2
    done
  done
done < "$input"
