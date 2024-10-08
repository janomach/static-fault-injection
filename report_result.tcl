# log signals
log -r ${halt_signal}
log -r ${timeout_signal}
log -r ${fail_signal}
log -r ${app_result}

when "${halt_signal} == 1" {
    # evaluate result
    set timeout [ examine ${timeout_signal} ]
    set failure [ examine ${fail_signal} ]
    set result [ examine ${app_result} ]
    if { ${timeout} == "1" } {
        echo "Timeout"
        set outcome 3
    } elseif { ${failure} == "1" } {
        echo "Core failure"
        set outcome 4
    } elseif { ${result} == "0" } {
        echo "Run finished sucesfully"
        set outcome 0
    } elseif { ${result} == "1" } {
        echo "Unexpected app finish"
        set outcome 1
    } elseif { ${result} == "2" } {
        echo "Incorrect result"
        set outcome 2
    } else {
        echo "Unknown failure"
        set outcome 5
    }
    set cc [expr $now/$clock_period]
    echo "Outcome: $outcome, Clock cycles: $cc; $timeout $failure $result"
    set results_file [open "${work_dir}/core_report.txt" a+]
    puts $results_file "$outcome,$cc"
    close $results_file
    stop
}

run -all
exit -force

