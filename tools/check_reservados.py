import re, glob, sys
ev = ("state_entry state_exit touch_start touch touch_end collision_start collision collision_end land_collision_start "
      "land_collision land_collision_end timer listen sensor no_sensor control money email at_target not_at_target at_rot_target "
      "not_at_rot_target run_time_permissions changed attach dataserver moving_start moving_end object_rez remote_data "
      "http_response http_request link_message on_rez transaction_result path_update experience_permissions "
      "experience_permissions_denied final_damage state default jump return if else for do while event").split()
base = sys.argv[1] if len(sys.argv) > 1 else '.'
bad = 0
for f in sorted(glob.glob(base + '/*.lsl')):
    s = open(f, encoding='utf-8').read()
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'"[^"\n]*"', '""', s)
    for m in re.finditer(r'\b(integer|float|string|key|vector|rotation|list)\s+([A-Za-z_]\w*)', s):
        if m.group(2) in ev:
            bad += 1
            print(f, '-> nome reservado:', m.group(2), '|', s[max(0, m.start() - 15):m.end() + 12].replace('\n', ' '))
print('problemas:', bad)
