# Static Fault Injection
This repository contains scripts for static fault injection (FI) into RTL design resources (wires, registers) during simulation.
It is static because the faults are generated before the simulation and then injected during the simulation.
Any fault is created by forcing the state of a selected RTL resource (a target) to the opposite value in the middle of the clock cycle for the duration of one clock cycle. 
This means that if the affected resource is a register, it will hold the faulty value until the design rewrites it.
It is possible to define minimal and maximal delay between two fault injections in the whole design, and the script generates a random FI delay within those constraints.
The time of the first FI is randomly generated, and then the next FIs are performed in increments of the previously generated FI delay.
It means that in each FI campaign (simulation with FI), the average delay between FI is constant, but the delay and start of the FI are different.

# Fault Injection Groups
The RTL targets can be sorted into distinct FI groups.
Each group has its assigned footprint (area) at the final chip, so the probability of faults among all groups can be fairly scaled.
It means that even if two groups have the same footprint but a different count of FI targets, the probability of fault within the group remains the same.
The footprint should be based on the data from the synthesis of the targeted system.

Fault injection generation methodology:
![FI generation](https://github.com/janomach/static-fault-injection/blob/main/doc/fi_generation.png)

# Usage
The [FI campaign script](https://github.com/janomach/static-fault-injection/blob/main/fi_campaign.sh) can be modified according to the targeted design and type of fault injection analysis.
Refer to it for more to see all the options.

The script requires the list of RTL targets for fault injection.
The [replicator script](https://github.com/janomach/static-fault-injection/blob/main/replicator.sh) can be used to expand arrays and vectors of the defined RTL resources into the individual single-bit tragets, that can be used as fault injection targets.

Each fault injection campaign ends with [reporting](https://github.com/janomach/static-fault-injection/blob/main/report_result.tcl) from the RTL simulator.

# Examples
This repository was developed for reliability assesment of the [Hardisc](https://github.com/janomach/the-hardisc) RISC-V core.
Refer to the repository for the example usage of the FI scripts.

# Simulator Support
The scripts were tested with the ModelSim 2020.1 and QuestaSim 2021.4.