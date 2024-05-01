batt_info() {

  local i=
  local info=
  local voltNow_=
  local currNow=
  local powerNow=
  local factor=
  local one="${1//,/|}"
  set +eu


  # calculator
  calc2() {
    awk "BEGIN {print $*}" | tr , . | xargs printf %.2f
  }


  dtr_conv_factor() {
    factor=${2-}
    if [ -z "$factor" ]; then
      case $1 in
        0) factor=1;;
        *) [ $1 -lt 16000 ] && factor=1000 || factor=1000000;;
      esac
    fi
  }


  # raw battery info from the kernel's battery interface
  info="$(
    { grep . $battCapacity $battStatus $currFile $temp $voltNow 2>/dev/null || :; } \
      | sed "s|.*/||; s/:/ /; s/^batt_vol/voltage_now/; s/^batt_temp/temp/" | sort
  )"


  # determine the correct charging status
  not_charging || :
  info="$(echo "$info" | sed "s/^status .*/status $_status/")"


  # because MediaTek is weird
  [ ! -d /proc/mtk_battery_cmd ] || {
    echo "$info" | grep '^current_now ' > /dev/null \
      || info="${info/batteryaveragecurrent/current_now}"
  }


  # append %
  info="$(echo "$info" | sed -E "s/^capacity (.*)/level \1%/")"


  # convert temp to ℃
  info="$(echo "$info" | sed "s/^temp .*/temp $(($(cat $temp) / 10))℃/")"


  # parse CURRENT_NOW & convert to Amps
  currNow=$(echo "$info" | sed -n "s/^current_now //p")
  dtr_conv_factor ${currNow#-} ${ampFactor:-$ampFactor_}
  currNow=$(calc2 ${currNow:-0} / $factor)


  # add/remove negative sign
  case $currNow in
    0.00)
      :
    ;;
    *)
      if [ $_status = Discharging ]; then
        currNow=-${currNow#-}
      elif [ $_status = Charging ]; then
        currNow=${currNow#-}
      fi
    ;;
  esac


  # parse VOLTAGE_NOW & convert to Volts
  voltNow_=$(echo "$info" | sed -n "s/^voltage_now //p")
  dtr_conv_factor $voltNow_ ${voltFactor-}
  voltNow_=$(calc2 ${voltNow_:-0} / $factor)


  # calculate POWER_NOW (Watts)
  powerNow=$(calc2 $currNow \* $voltNow_)


  {
    # print raw battery info
    echo "$info" | grep -Ev '^(current|voltage)_now '

    # print current_now, voltage_now and power_now
    echo "
current_now ${currNow}A
voltage_now ${voltNow_}V
power_now ${powerNow}W"


  # power supply info
  for i in $(online_f); do
    if [ -f $i ] && [ $(cat $i) -eq 1 ]; then
      i=${i%/*}
      power_supply_type=$(cat $i/real_type 2>/dev/null || echo $i)

      echo "
charge_type $power_supply_type"

      power_supply_amps=$(dtr_conv_factor $(cat $i/*current_now | tail -n 1) ${ampFactor:-$ampFactor_})

      if [ 0${power_supply_amps%.*} -gt 0 ]; then
        power_supply_volts=$(dtr_conv_factor $(cat $i/voltage_now) ${voltFactor-})
        power_supply_watts=$(calc2 $power_supply_amps \* $power_supply_volts)
        consumed_watts=$(calc2 $power_supply_watts - $powernow)

        echo "power_supply_amps $power_supply_amps
power_supply_volts $power_supply_volts
power_supply_watts $power_supply_watts
consumed_watts $consumed_watts"
      fi

      break
    fi
  done 2>/dev/null || :


  # online status (for debugging)
  echo
  grep . */online | sed 's/:/ /'


  } | grep -Ei "${one:-.*}" || :
}
