set ::env(LM_LICENSE_FILE) {D:\Mentor_Graphics_ModelSim_SE-64_10.6e\win64\LICENSE.TXT}
set ::env(MGLS_LICENSE_FILE) {D:\Mentor_Graphics_ModelSim_SE-64_10.6e\win64\LICENSE.TXT}
set ::env(MODELSIM) {D:\vivado_project\project_2\modelsim.ini}
set modelsim_bin {D:\Mentor_Graphics_ModelSim_SE-64_10.6e\win64}
if {![info exists ::env(PATH)] || [string first $modelsim_bin $::env(PATH)] < 0} {
    set ::env(PATH) "$modelsim_bin;$::env(PATH)"
}

puts "ModelSim environment configured for this Vivado session:"
puts "  LM_LICENSE_FILE=$::env(LM_LICENSE_FILE)"
puts "  MGLS_LICENSE_FILE=$::env(MGLS_LICENSE_FILE)"
puts "  MODELSIM=$::env(MODELSIM)"
puts "  Added to PATH: $modelsim_bin"
