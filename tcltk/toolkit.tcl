#-----------------------------------------------------
# Magic/TCL general-purpose toolkit procedures
#-----------------------------------------------------
# Tim Edwards
# February 11, 2007
# Revision 0
# December 15, 2016
# Revision 1
# October 29, 2020
# Revision 2	(names are hashed from properties)
# March 9, 2021
# Added spice-to-layout procedure
#--------------------------------------------------------------
# Sets up the environment for a toolkit.  The toolkit must
# supply a namespace that is the "library name".  For each
# parameter-defined device ("gencell") type, the toolkit must
# supply five procedures:
#
# 1. ${library}::${gencell_type}_defaults {}
# 2. ${library}::${gencell_type}_convert  {parameters}
# 3. ${library}::${gencell_type}_dialog   {parameters}
# 4. ${library}::${gencell_type}_check    {parameters}
# 5. ${library}::${gencell_type}_draw     {parameters}
#
# The first defines the parameters used by the gencell, and
# declares default parameters to use when first generating
# the window that prompts for the device parameters prior to
# creating the device.  The second converts between parameters
# in a SPICE netlist and parameters used by the dialog,
# performing units conversion and parameter name conversion as
# needed.  The third builds the dialog window for entering
# device parameters.  The fourth checks the parameters for
# legal values.  The fifth draws the device.
#
# If "library" is not specified then it defaults to "toolkit".
# Otherwise, where specified, the name "gencell_fullname"
# is equivalent to "${library}::${gencell_type}"
#
# Each gencell is defined by cell properties as created by
# the "cellname property" command.  Specific properties used
# by the toolkit are:
#
# library    --- name of library (see above, default "toolkit")
# gencell    --- base name of gencell (gencell_type, above)
# parameters --- list of gencell parameter-value pairs
#--------------------------------------------------------------

# Initialize toolkit menus to the wrapper window

global Opts

#----------------------------------------------------------------
# Add a menu button to the Magic wrapper window for the toolkit
#----------------------------------------------------------------

proc magic::add_toolkit_menu {framename button_text {library toolkit}} {
   menubutton ${framename}.titlebar.mbuttons.${library} \
		-text $button_text \
		-relief raised \
		-menu ${framename}.titlebar.mbuttons.${library}.toolmenu \
		-borderwidth 2

   menu ${framename}.titlebar.mbuttons.${library}.toolmenu -tearoff 0
   pack ${framename}.titlebar.mbuttons.${library} -side left
}

#-----------------------------------------------------------------
# Add a menu item to the toolkit menu calling the default function
#-----------------------------------------------------------------

proc magic::add_toolkit_button {framename button_text gencell_type \
		{library toolkit} args} {
   set m ${framename}.titlebar.mbuttons.${library}.toolmenu
   $m add command -label "$button_text" -command \
	"magic::gencell $library::$gencell_type {} $args"
}

#----------------------------------------------------------------
# Add a menu item to the toolkit menu that calls the provided
# function
#----------------------------------------------------------------

proc magic::add_toolkit_command {framename button_text \
		command {library toolkit} args} {
   set m ${framename}.titlebar.mbuttons.${library}.toolmenu
   $m add command -label "$button_text" -command "$command $args"
}

#----------------------------------------------------------------
# Add a separator to the toolkit menu
#----------------------------------------------------------------

proc magic::add_toolkit_separator {framename {library toolkit}} {
   set m ${framename}.titlebar.mbuttons.${library}.toolmenu
   $m add separator
}

#-----------------------------------------------------
# Add "Ctrl-P" key callback for device selection
#-----------------------------------------------------

magic::macro ^P "magic::gencell {} ; raise .params"

#-------------------------------------------------------------
# Add tag callback to select to update the gencell window
#-------------------------------------------------------------

magic::tag select "[magic::tag select]; magic::gencell_update %1"

#--------------------------------------------------------------
# Supporting procedures for netlist_to_layout procedure
#--------------------------------------------------------------

# move_forward_by_width --
#
#    Given an instance name, find the instance and position the
#    cursor box at the right side of the instance.

proc magic::move_forward_by_width {instname} {
    select cell $instname
    set anum [lindex [array -list count] 1]
    set xpitch [lindex [array -list pitch] 0]
    set bbox [box values]
    set posx [lindex $bbox 0]
    set posy [lindex $bbox 1]
    set width [expr [lindex $bbox 2] - $posx]
    set posx [expr $posx + $width + $xpitch * $anum]
    box position ${posx}i ${posy}i
    return [lindex $bbox 3]
}

# get_and_move_inst --
#
#    Given a cell name, creat an instance of the cell named "instname"
#    at the current cursor box position.  If option "anum" is given
#    and > 1, then array the cell.

proc magic::get_and_move_inst {cellname instname {anum 1}} {
    set newinst [getcell $cellname]
    select cell $newinst
    if {$newinst == ""} {return}
    identify $instname
    if {$anum > 1} {array 1 $anum}
    set bbox [box values]
    set posx [lindex $bbox 2]
    set posy [lindex $bbox 1]
    box position ${posx}i ${posy}i
    return [lindex $bbox 3]
}

# create_new_pin --
#
#    Create a new pin of size 1um x 1um at the current cursor box
#    location.  If "layer" is given, then create the pin on the
#    given layer.  Otherwise, the pin is created on the m1 layer.

proc magic::create_new_pin {pinname portnum {layer m1}} {
    box size 1um 1um
    paint $layer
    label $pinname FreeSans 16 0 0 0 c $layer
    port make $portnum
    box move s 2um
}

# generate_layout_add --
#
#    Add a new subcircuit to a layout and seed it with components
#    as found in the list "complist", and add pins according to the
#    pin names in "subpins".  Each entry in "complist" is a single
#    device line from a SPICE file.

proc magic::generate_layout_add {subname subpins complist library} {
    global PDKNAMESPACE

    # Create a new subcircuit.
    load $subname -quiet

    # In the case where subcells of circuit "subname" do not exist,
    # delete the placeholders so that they can be regenerated.

    set children [cellname list children $subname]
    foreach child $children {
	set flags [cellname flags $child]
	foreach flag $flags {
	    if {$flag == "not-found"} {
		set insts [cellname list instances $child]
		foreach inst $insts {
		    select cell $inst
		    delete
		}
		cellname delete $child
	    }
	}
    }

    box 0 0 0 0

    # Generate pins
    if {[llength $subpins] > 0} {
	set pinlist [split $subpins]
	set i 0
	foreach pin $pinlist {
	    # Escape [ and ] in pin name
	    set pin_esc [string map {\[ \\\[ \] \\\]} $pin]
	    magic::create_new_pin $pin_esc $i
	    incr i
	}
    }

    # Set initial position for importing cells
    box size 0 0
    set posx 0
    set posy [expr {round(3 / [cif scale out])}]
    box position ${posx}i ${posy}i

    # Seed layout with components
    foreach comp $complist {
	set pinlist {}
	set paramlist {}

	# NOTE:  This routine deals with subcircuit calls and devices
	# with models.  It needs to determine when a device is instantiated
	# without a model, and ignore such devices.

	# Parse SPICE line into pins, device name, and parameters.  Make
	# sure parameters incorporate quoted expressions as {} or ''.

	set rest $comp
	while {$rest != ""} {
	    if {[regexp -nocase {^[ \t]*[^= \t]+=[^=]+} $rest]} {
		break
	    } elseif {[regexp -nocase {^[ \t]*([^ \t]+)[ \t]*(.*)$} $rest \
			valid token rest]} {
		lappend pinlist $token
	    } else {
		set rest ""
	    }
	}

	while {$rest != ""} {
	    if {[regexp -nocase {^([^= \t]+)=\'([^\']+)\'[ \t]*(.*)} $rest \
			valid pname value rest]} {
		lappend paramlist [list $pname "{$value}"]
	    } elseif {[regexp -nocase {^([^= \t]+)=\{([^\}]+)\}[ \t]*(.*)} $rest \
			valid pname value rest]} {
		lappend paramlist [list $pname "{$value}"]
	    } elseif {[regexp -nocase {^([^= \t]+)=([^= \t]+)[ \t]*(.*)} $rest \
			valid pname value rest]} {
		lappend paramlist [list $pname $value]
	    } else {
		puts stderr "Error parsing line \"$comp\""
		puts stderr "at:  \"$rest\""
		set rest ""
	    }
	}

	if {[llength $pinlist] < 2} {
	    puts stderr "Error:  No device type found in line \"$comp\""
	    puts stderr "Tokens found are: \"$pinlist\""
	    continue
	}

	set instname [lindex $pinlist 0]
	set devtype [lindex $pinlist end]
	set pinlist [lrange $pinlist 0 end-1]

	set mult 1
	foreach param $paramlist {
	    set parmname [lindex $param 0]
	    set parmval [lindex $param 1]
	    if {[string toupper $parmname] == "M"} {
		if {[catch {set mult [expr {int($parmval)}]}]} {
		    set mult [expr [string trim $parmval "'"]]
		}
	    }
	}

        # devtype is assumed to be in library.  If not, it will attempt to
	# use 'getcell' on devtype.  Note that this code depends on the
	# PDK setting varible PDKNAMESPACE.

	if {$library != ""} {
	    set libdev ${library}::${devtype}
	} else {
	    set libdev ${PDKNAMESPACE}::${devtype}
	}

	set outparts {}
	lappend outparts "magic::gencell $libdev $instname"

	# Output all parameters.  Parameters not used by the toolkit are
	# ignored by the toolkit.

	lappend outparts "-spice"
	foreach param $paramlist {
	    lappend outparts [string tolower [lindex $param 0]]
	    lappend outparts [lindex $param 1]
	}

	if {[catch {eval [join $outparts]}]} {
	    # Assume this is not a gencell, and get an instance.
	    magic::get_and_move_inst $devtype $instname $mult
	} else {
	    # Move forward for next gencell
	    magic::move_forward_by_width $instname
	}
    }
    save $subname
}

#--------------------------------------------------------------
# Wrapper for generating an initial layout from a SPICE netlist
# using the defined PDK toolkit procedures
#
#    "netfile" is the name of a SPICE netlist
#    "library" is the name of the PDK library namespace
#--------------------------------------------------------------

proc magic::netlist_to_layout {netfile library} {

   if {![file exists $netfile]} {
      puts stderr "No such file $netfile"
      return
   }

   # Read data from file.  Remove comment lines and concatenate
   # continuation lines.

   set topname [file rootname [file tail $netfile]]
   puts stdout "Creating layout from [file tail $netfile]"

   if {[file ext $netfile] == ".cdl"} {
      set is_cdl true
   } else {
      set is_cdl false
   }

   if [catch {open $netfile r} fnet] {
      puts stderr "Error:  Cannot open file \"$netfile\" for reading."
      return
   }

   set fdata {}
   set lastline ""
   while {[gets $fnet line] >= 0} {
       # Handle CDL format *.PININFO (convert to .PININFO ...)
       if {$is_cdl && ([string range $line 0 1] == "*.")} {
           if {[string tolower [string range $line 2 8]] == "pininfo"} {
               set line [string range $line 1 end]
           }
       }
       if {[string index $line 0] != "*"} {
           if {[string index $line 0] == "+"} {
               if {[string range $line end end] != " "} {
                  append lastline " "
               }
               append lastline [string range $line 1 end]
           } else {
               lappend fdata $lastline
               set lastline $line
           }
       }
   }
   lappend fdata $lastline
   close $fnet

   set insub false
   set incmd false
   set subname ""
   set subpins ""
   set complist {} 
   set toplist {}

   # suspendall

   set ignorekeys {.global .ic .option .end}

   # Parse the file
   foreach line $fdata {
      if {$incmd} {
	 if {[regexp -nocase {^[ \t]*\.endc} $line]} {
	    set incmd false
	 }
      } elseif {! $insub} {
         set ftokens [split $line]
         set keyword [string tolower [lindex $ftokens 0]]

         if {[lsearch $ignorekeys $keyword] != -1} { 
	    continue
         } elseif {$keyword == ".command"} {
	    set incmd true
         } elseif {$keyword == ".subckt"} {
	    set subname [lindex $ftokens 1]
	    set subpins [lrange $ftokens 2 end]
	    set insub true
         } elseif {[regexp -nocase {^[xmcrdq]([^ \t]+)[ \t](.*)$} $line \
		    valid instname rest]} {
	    lappend toplist $line
         } elseif {[regexp -nocase {^[ivbe]([^ \t]+)[ \t](.*)$} $line \
		    valid instname rest]} {
	    # These are testbench devices and should be ignored
	    continue
         }
      } else {
	 if {[regexp -nocase {^[ \t]*\.ends} $line]} {
	    set insub false
	    magic::generate_layout_add $subname $subpins $complist $library
	    set subname ""
	    set subpins ""
	    set complist {}
         } elseif {[regexp -nocase {^[xmcrdq]([^ \t]+)[ \t](.*)$} $line \
		    valid instname rest]} {
	    lappend complist $line
         } elseif {[regexp -nocase {^[ivbe]([^ \t]+)[ \t](.*)$} $line \
		    valid instname rest]} {
	    # These are testbench devices and should be ignored
	    continue
	 }
      }
   }

   # Add in any top-level components (not in subcircuits)
   if {[llength $toplist] > 0} {
      magic::generate_layout_add $topname "" $toplist $library
   }

   # resumeall
}

#-------------------------------------------------------------
# gencell
#
#   Main routine to call a cell from either a menu button or
#   from a script or command line.  The name of the device
#   is required, followed by the name of the instance, followed
#   by an optional list of parameters.  Handling depends on
#   instname and args:
#
#   gencell_name is either the name of an instance or the name
#   of the gencell in the form <library>::<device>.
#
#   name        args      action
#-----------------------------------------------------------------
#   none        empty     interactive, new device w/defaults
#   none        specified interactive, new device w/parameters
#   instname    empty     interactive, edit device
#   instname    specified non-interactive, change device
#   device      empty     non-interactive, new device w/defaults
#   device	specified non-interactive, new device w/parameters
#
#-------------------------------------------------------------
# Also, if instname is empty and gencell_name is not specified,
# and if a device is selected in the layout, then gencell
# behaves like line 3 above (instname exists, args is empty).
# Note that macro Ctrl-P calls gencell this way.  If gencell_name
# is not specified and nothing is selected, then gencell{}
# does nothing.
#
# "args" must be a list of the cell parameters in key:value pairs,
# and an odd number is not legal;  the exception is that if the
# first argument is "-spice", then the list of parameters is
# expected to be in the format used in a SPICE netlist, and the
# parameter names and values will be treated accordingly.
#-------------------------------------------------------------

proc magic::gencell {gencell_name {instname {}} args} {

    # Pull "-spice" out of args, if it is the first argument
    if {[lindex $args 0] == "-spice"} {
	set spicemode 1
	set args [lrange $args 1 end]
    } else {
	set spicemode 0
    }
    set argpar [dict create {*}$args]

    if {$gencell_name == {}} {
	# Find selected item  (to-do:  handle multiple selections)

	set wlist [what -list]
	set clist [lindex $wlist 2]
	set ccell [lindex $clist 0]
	set ginst [lindex $ccell 0]
	set gname [lindex $ccell 1]
	set library [cellname list property $gname library]
	if {$library == {}} {
	    set library toolkit
        }
	set gencell_type [cellname list property $gname gencell]
	if {$gencell_type == {}} {
	   if {![regexp {^(.*)_[0-9]*$} $gname valid gencell_type]} {
	      # Error message
	      error "No gencell device is selected!"
	   }
	}
        # need to incorporate argpar?
        set parameters [cellname list property $gname parameters]
	set parameters [magic::gencell_defaults $gencell_type $library $parameters]
	magic::gencell_dialog $ginst $gencell_type $library $parameters
    } else {
	# Parse out library name from gencell_name, otherwise default
	# library is assumed to be "toolkit".
	if {[regexp {^([^:]+)::([^:]+)$} $gencell_name valid library gencell_type] \
			== 0} {
	    set library "toolkit"
	    set gencell_type $gencell_name
	}

    	# Check that the device exists as a gencell, or else return an error
    	if {[namespace eval ::${library} info commands ${gencell_type}_convert] == ""} {
	    error "No import routine for ${library} library cell ${gencell_type}!"
    	}

	if {$instname == {}} {
	    # Case:  Interactive, new device with parameters in args (if any)
	    if {$spicemode == 1} {
		# Legal not to have a *_convert routine
		if {[info commands ${library}::${gencell_type}_convert] != ""} {
		    set argpar [${library}::${gencell_type}_convert $argpar]
		}
	    }
	    set parameters [magic::gencell_defaults $gencell_type $library $argpar]
	    magic::gencell_dialog {} $gencell_type $library $parameters
	} else {
	    # Check if instance exists or not in the cell
	    set cellname [instance list celldef $instname]

	    if {$cellname != ""} {
		# Case:  Change existing instance, parameters in args (if any)
		select cell $instname
		set devparms [cellname list property $cellname parameters]
	        set parameters [magic::gencell_defaults $gencell_type $library $devparms]
		if {[dict exists $parameters nocell]} {
		    set arcount [array -list count]
		    set arpitch [array -list pitch]

		    dict set parameters nx [lindex $arcount 1]
		    dict set parameters ny [lindex $arcount 3]
		    dict set parameters pitchx $delx
		    dict set parameters pitchy $dely
		}
		if {[dict size $argpar] == 0} {
		    # No changes entered on the command line, so start dialog
		    magic::gencell_dialog $instname $gencell_type $library $parameters
		} else {
		    # Apply specified changes without invoking the dialog
		    if {$spicemode == 1} {
			set argpar [${library}::${gencell_type}_convert $argpar]
		    }
		    set parameters [dict merge $parameters $argpar]
		    magic::gencell_change $instname $gencell_type $library $parameters
		}
	    } else {
		# Case:  Non-interactive, create new device with parameters
		# in args (if any)
		if {$spicemode == 1} {
		    set argpar [${library}::${gencell_type}_convert $argpar]
		}
	        set parameters [magic::gencell_defaults $gencell_type $library $argpar]
		set inst_defaultname [magic::gencell_create \
				$gencell_type $library $parameters]
		select cell $inst_defaultname
		identify $instname
	    }
	}
    }
    return 0
}

#-------------------------------------------------------------
# gencell_makecell
#
# This is a variation of magic::gencell and is used to generate
# a cell and return the cell name without creating or placing
# an instance.
#-------------------------------------------------------------

proc magic::gencell_makecell {gencell_fullname args} {

    set argpar [dict create {*}$args]
    set gencell_basename [namespace tail $gencell_fullname]
    set library [namespace qualifiers $gencell_fullname]
    set parameters [magic::gencell_defaults $gencell_basename $library $argpar]
    set gsuffix [magic::get_gencell_hash ${parameters}]
    set gname ${gencell_basename}_${gsuffix}
    suspendall
    cellname create $gname
    pushstack $gname
    if {[catch {${library}::${gencell_basename}_draw $parameters} drawerr]} {
        puts stderr $drawerr
    }
    property library $library
    property gencell $gencell_basename
    property parameters $parameters
    popstack
    resumeall
    return $gname
}

#-------------------------------------------------------------
# gencell_getparams
#
#   Go through the parameter window and collect all of the
#   named parameters and their values.  Return the result as
#   a dictionary.
#-------------------------------------------------------------

proc magic::gencell_getparams {} {
   set parameters [dict create]
   set slist [grid slaves .params.body.area.edits]
   foreach s $slist {
      if {[regexp {^\.params\.body\.area\.edits\.(.*)_ent$} $s valid pname] != 0} {
	 set value [subst \$magic::${pname}_val]
      } elseif {[regexp {^\.params\.body\.area\.edits\.(.*)_chk$} $s valid pname] != 0} {
	 set value [subst \$magic::${pname}_val]
      } elseif {[regexp {^\.params\.body\.area\.edits\.(.*)_sel$} $s valid pname] != 0} {
	 set value [subst \$magic::${pname}_val]
      }
      dict set parameters $pname $value
   }
   return $parameters
}

#-------------------------------------------------------------
# gencell_setparams
#
#   Fill in values in the dialog from a set of parameters
#-------------------------------------------------------------

proc magic::gencell_setparams {parameters} {
   if {[catch {set state [wm state .params]}]} {return}
   set slist [grid slaves .params.body.area.edits]
   foreach s $slist {
      # ignore .params.body.area.edits.gencell_sel, as that does not exist in the
      # parameters dictionary
      if {$s == ".params.body.area.edits.gencell_sel"} {continue}
      if {[regexp {^.params.body.area.edits.(.*)_ent$} $s valid pname] != 0} {
	 set value [dict get $parameters $pname]
         set magic::${pname}_val $value
      } elseif {[regexp {^.params.body.area.edits.(.*)_chk$} $s valid pname] != 0} {
	 set value [dict get $parameters $pname]
         set magic::${pname}_val $value
      } elseif {[regexp {^.params.body.area.edits.(.*)_sel$} $s valid pname] != 0} {
	 set value [dict get $parameters $pname]
         set magic::${pname}_val $value
	 .params.body.area.edits.${pname}_sel configure -text $value
      } elseif {[regexp {^.params.body.area.edits.(.*)_txt$} $s valid pname] != 0} {
	 if {[dict exists $parameters $pname]} {
	    set value [dict get $parameters $pname]
	    .params.body.area.edits.${pname}_txt configure -text $value
	 }
      }
   }
}

#-------------------------------------------------------------
# gencell_change
#
#   Recreate a gencell with new parameters.  Note that because
#   each cellname is uniquely identified by the (hashed) set
#   of parameters, changing parameters effectively means
#   creating a new cell.  If the original cell has parents
#   other than the parent of the instance being changed, then
#   it is retained;  otherwise, it is deleted.  The instance
#   being edited gets replaced by an instance of the new cell.
#   If the instance name was the cellname + suffix, then the
#   instance name is regenerated.  Otherwise, the instance
#   name is retained.
#-------------------------------------------------------------

proc magic::gencell_change {instname gencell_type library parameters} {
    global Opts
    suspendall

    set newinstname $instname
    if {$parameters == {}} {
        # Get device defaults
	set pdefaults [${library}::${gencell_type}_defaults]
        # Pull user-entered values from dialog
        set parameters [dict merge $pdefaults [magic::gencell_getparams]]
	set newinstname [.params.title.ient get]
	if {$newinstname == "(default)"} {set newinstname $instname}
	if {$newinstname == $instname} {set newinstname $instname}
	if {[instance list exists $newinstname] != ""} {set newinstname $instname}
    }
    if {[dict exists $parameters gencell]} {
        # Setting special parameter "gencell" forces the gencell to change type
	set gencell_type [dict get $parameters gencell]
    }
    if {[catch {set parameters [${library}::${gencell_type}_check $parameters]} \
		checkerr]} {
	puts stderr $checkerr
    }
    magic::gencell_setparams $parameters
    if {[dict exists $parameters gencell]} {
	set parameters [dict remove $parameters gencell]
    }

    set old_gname [instance list celldef $instname]
    set gsuffix [magic::get_gencell_hash ${parameters}]
    set gname ${gencell_type}_${gsuffix}

    # Guard against instance having been deleted.  Also, if parameters have not
    # changed as evidenced by the cell suffix not changing, then nothing further
    # needs to be done.
    if {$gname == "" || $gname == $old_gname} {
	resumeall
        return
    }

    set snaptype [snap list]
    snap internal
    set savebox [box values]

    catch {setpoint 0 0 $Opts(focus)}
    if [dict exists $parameters nocell] {
        select cell $instname
	set abox [instance list abutment]
	delete
	if {$abox != ""} {box values {*}$abox}
	if {[catch {set newinst [${library}::${gencell_type}_draw $parameters]} \
		drawerr]} {
	    puts stderr $drawerr
	}
        select cell $newinst
    } elseif {[cellname list exists $gname] != 0} {
	# If there is already a cell of this type then it is only required to
	# remove the instance and replace it with an instance of the cell
        select cell $instname
	# check rotate/flip before replacing and replace with same
	set orient [instance list orientation]
	set abox [instance list abutment]
	delete

	if {$abox != ""} {box values {*}$abox}
	set newinstname [getcell $gname $orient]
        select cell $newinstname
	expand

	# If the old instance name was not formed from the old cell name,
	# then keep the old instance name.
	if {[string first $old_gname $instname] != 0} {
	    set newinstname $instname
	}

	if {[cellname list parents $old_gname] == []} {
	    # If the original cell has no intances left, delete it.  It can
	    # be regenerated if and when necessary.
	    cellname delete $old_gname
	}

    } else {
        select cell $instname
	set orient [instance list orientation]
	set abox [instance list abutment]
	delete

	# There is no cell of this name, so generate one and instantiate it.
	if {$abox != ""} {box values {*}$abox}
	set newinstname [magic::gencell_create $gencell_type $library $parameters $orient]
	select cell $newinstname

	# If the old instance name was not formed from the old cell name,
	# then keep the old instance name.
	if {[string first $old_gname $instname] != 0} {
	    set newinstname $instname
	} else {
	    # The buttons "Apply" and "Okay" need to be changed for the new
	    # instance name
	    catch {.params.buttons.apply config -command \
			"magic::gencell_change $newinstname $gencell_type $library {}"}
	    catch {.params.buttons.okay config -command \
			"magic::gencell_change $newinstname $gencell_type $library {} ;\
			destroy .params"}
	}
    }
    identify $newinstname
    eval "box values $savebox"
    snap $snaptype

    # Update window
    if {$gname != $old_gname} {
        catch {.params.title.glab configure -text "$gname"}
    }
    if {$instname != $newinstname} {
        catch {.params.title.ient delete 0 end}
        catch {.params.title.ient insert 0 "$newinstname"}
    }

    resumeall
    redraw
}

#-------------------------------------------------------------
# gencell_change_orig
#
#   Original version:  Redraw a gencell with new parameters,
#   without changing the cell itself.
#-------------------------------------------------------------

proc magic::gencell_change_orig {instname gencell_type library parameters} {
    global Opts
    suspendall

    set newinstname $instname
    if {$parameters == {}} {
        # Get device defaults
	set pdefaults [${library}::${gencell_type}_defaults]
        # Pull user-entered values from dialog
        set parameters [dict merge $pdefaults [magic::gencell_getparams]]
	set newinstname [.params.title.ient get]
	if {$newinstname == "(default)"} {set newinstname $instname}
	if {$newinstname == $instname} {set newinstname $instname}
	if {[instance list exists $newinstname] != ""} {set newinstname $instname}
    }
    if {[dict exists $parameters gencell]} {
        # Setting special parameter "gencell" forces the gencell to change type
	set gencell_type [dict get $parameters gencell]
    }
    if {[catch {set parameters [${library}::${gencell_type}_check $parameters]} \
		checkerr]} {
	puts stderr $checkerr
    }
    magic::gencell_setparams $parameters
    if {[dict exists $parameters gencell]} {
	set parameters [dict remove $parameters gencell]
    }

    set gname [instance list celldef $instname]

    # Guard against instance having been deleted
    if {$gname == ""} {
	resumeall
        return
    }

    set snaptype [snap list]
    snap internal
    set savebox [box values]

    catch {setpoint 0 0 $Opts(focus)}
    if [dict exists $parameters nocell] {
        select cell $instname
	delete
	if {[catch {set newinst [${library}::${gencell_type}_draw $parameters]} \
		drawerr]} {
	    puts stderr $drawerr
	}
        select cell $newinst
    } else {
	pushstack $gname
	select cell
	tech unlock *
	erase *
	if {[catch {${library}::${gencell_type}_draw $parameters} drawerr]} {
	    puts stderr $drawerr
	}
	property parameters $parameters
	property gencell ${gencell_type}
	tech revert
	popstack
        select cell $instname
    }
    identify $newinstname
    eval "box values $savebox"
    snap $snaptype
    resumeall
    redraw
}

#-------------------------------------------------------------
# Assign a unique name for a gencell
#
# Note:  This depends on the unlikelihood of the name
# existing in a cell on disk.  Only cells in memory are
# checked for name collisions.  Since the names will go
# into SPICE netlists, names must be unique when compared
# in a case-insensitive manner.  Using base-36 (alphabet and
# numbers), each gencell name with 6 randomized characters
# has a 1 in 4.6E-10 chance of reappearing.
#-------------------------------------------------------------

proc magic::get_gencell_name {gencell_type} {
    while {true} {
        set postfix ""
        for {set i 0} {$i < 6} {incr i} {
	    set pint [expr 48 + int(rand() * 36)]
	    if {$pint > 57} {set pint [expr $pint + 39]}
	    append postfix [format %c $pint]
	}
	if {[cellname list exists ${gencell_type}_$postfix] == 0} {break}
    }
    return ${gencell_type}_$postfix
}

#----------------------------------------------------------------
# get_gencell_hash
#
#   A better approach to the above.  Take the parameter
#   dictionary, and run all the values through a hash function
#   to generate a 30-bit value, then convert to base32.  This
#   gives a result that is repeatable for the same set of
#   parameter values with a very low probability of a collision.
#
#   The hash function is similar to elfhash but reduced from 32
#   to 30 bits so that the result can form a 6-character value
#   in base32 with all characters being valid for a SPICE subcell
#   name (e.g., alphanumeric only and case-insensitive).
#----------------------------------------------------------------

proc magic::get_gencell_hash {parameters} {
    set hash 0
    # Apply hash
    dict for {key value} $parameters {
	foreach s [split $value {}] {
	    set hash [expr {($hash << 4) + [scan $s %c]}]
	    set high [expr {$hash & 0x03c0000000}]
	    set hash [expr {$hash ^ ($high >> 30)}]
	    set hash [expr {$hash & (~$high)}]
	}
    }
    # Divide hash up into 5 bit values and convert to base32
    # using letters A-Z less I and O, and digits 2-9.
    set cvals ""
    for {set i 0} {$i < 6} {incr i} {
	set oval [expr {($hash >> ($i * 5)) & 0x1f}]
        if {$oval < 8} {
	    set bval [expr {$oval + 50}]
	} elseif {$oval < 16} {
	    set bval [expr {$oval + 57}]
	} elseif {$oval < 21} {
	    set bval [expr {$oval + 58}]
	} else {
	    set bval [expr {$oval + 59}]
	}
	append cvals [binary format c* $bval]
    }
    return $cvals
}

#-------------------------------------------------------------
# gencell_create
#
#   Instantiate a new gencell called $gname.  If $gname
#   does not already exist, create it by calling its
#   drawing routine.
#
#   Don't rely on pushbox/popbox since we don't know what
#   the drawing routine is going to do to the stack!
#-------------------------------------------------------------

proc magic::gencell_create {gencell_type library parameters {orient 0}} {
    global Opts
    suspendall

    set newinstname ""

    # Get device defaults
    if {$parameters == {}} {
        # Pull user-entered values from dialog
        set dialogparams [magic::gencell_getparams]
	if {[dict exists $dialogparams gencell]} {
	    # Setting special parameter "gencell" forces the gencell to change type
	    set gencell_type [dict get $dialogparams gencell]
	}
	set pdefaults [${library}::${gencell_type}_defaults]
        set parameters [dict merge $pdefaults $dialogparams]
	set newinstname [.params.title.ient get]
	if {$newinstname == "(default)"} {set newinstname ""}
	if {[instance list exists $newinstname] != ""} {set newinstname ""}
    } else {
	if {[dict exists $parameters gencell]} {
	    # Setting special parameter "gencell" forces the gencell to change type
	    set gencell_type [dict get $parameters gencell]
	}
	set pdefaults [${library}::${gencell_type}_defaults]
        set parameters [dict merge $pdefaults $parameters]
    }

    if {[catch {set parameters [${library}::${gencell_type}_check $parameters]} \
		checkerr]} {
	puts stderr $checkerr
    }
    magic::gencell_setparams $parameters
    if {[dict exists $parameters gencell]} {
	set parameters [dict remove $parameters gencell]
    }

    set snaptype [snap list]
    snap internal
    set savebox [box values]

    catch {setpoint 0 0 $Opts(focus)}
    if [dict exists $parameters nocell] {
	if {[catch {set instname [${library}::${gencell_type}_draw $parameters]} \				drawerr]} {
	    puts stderr $drawerr
	}
	set gname [instance list celldef $instname]
	eval "box values $savebox"
    } else {
        set gsuffix [magic::get_gencell_hash ${parameters}]
        set gname ${gencell_type}_${gsuffix}
	cellname create $gname
	pushstack $gname
	if {[catch {${library}::${gencell_type}_draw $parameters} drawerr]} {
	    puts stderr $drawerr
	}
	property library $library
	property gencell $gencell_type
	property parameters $parameters
	popstack
	eval "box values $savebox"
	set instname [getcell $gname $orient]
	expand
    }
    if {$newinstname != ""} {
	identify $newinstname
	set instname $newinstname
    }
    snap $snaptype
    resumeall
    redraw
    return $instname
}

#-----------------------------------------------------
#  Add a standard entry parameter to the gencell window
#-----------------------------------------------------

proc magic::add_entry {pname ptext parameters} {

   if [dict exists $parameters $pname] {
        set value [dict get $parameters $pname]
   } else {
       set value ""
   }

   set numrows [lindex [grid size .params.body.area.edits] 1]
   label .params.body.area.edits.${pname}_lab -text $ptext
   entry .params.body.area.edits.${pname}_ent -background white -textvariable magic::${pname}_val
   grid .params.body.area.edits.${pname}_lab -row $numrows -column 0 \
	-sticky ens -ipadx 5 -ipady 2
   grid .params.body.area.edits.${pname}_ent -row $numrows -column 1 \
	-sticky ewns -ipadx 5 -ipady 2
   .params.body.area.edits.${pname}_ent insert end $value
   set magic::${pname}_val $value
}

#----------------------------------------------------------
# Default entry callback, without any dependencies.  Each
# parameter changed
#----------------------------------------------------------

proc magic::add_check_callbacks {gencell_type library} {
    set wlist [winfo children .params.body.area.edits]
    foreach w $wlist {
        if {[regexp {\.params\.body\.area\.edits\.(.+)_ent} $w valid pname]} {
	    # Add callback on enter or focus out
	    bind $w <Return> \
			"magic::update_dialog {} $pname $gencell_type $library"
	    bind $w <FocusOut> \
			"magic::update_dialog {} $pname $gencell_type $library"
	}
    }
}

#----------------------------------------------------------
# Add a dependency between entries.  When one updates, the
# others will be recomputed according to the callback
# function.
#
# The callback function is passed the value of all
# parameters for the device, overridden by the values
# in the dialog.  The routine computes the dependent
# values and writes them back to the parameter dictionary.
# The callback function must return the modified parameters
# dictionary.
#
# Also handle dependencies on checkboxes and selection lists
#----------------------------------------------------------

proc magic::add_dependency {callback gencell_type library args} {
    if {[llength $args] == 0} {
	# If no arguments are given, do for all parameters
	set parameters ${library}::${gencell_type}_defaults
	magic::add_dependency $callback $gencell_type $library \
			{*}[dict keys $parameters]
	return
    }
    set clist [winfo children .params.body.area.edits]
    foreach pname $args {
        if {[lsearch $clist .params.body.area.edits.${pname}_ent] >= 0} {
	    # Add callback on enter or focus out
	    bind .params.body.area.edits.${pname}_ent <Return> \
			"magic::update_dialog $callback $pname $gencell_type $library"
	    bind .params.body.area.edits.${pname}_ent <FocusOut> \
			"magic::update_dialog $callback $pname $gencell_type $library"
	} elseif {[lsearch $clist .params.body.area.edits.${pname}_chk] >= 0} {
	    # Add callback on checkbox change state
	    .params.body.area.edits.${pname}_chk configure -command \
			"magic::update_dialog $callback $pname $gencell_type $library"
	} elseif {[lsearch $clist .params.body.area.edits.${pname}_sel] >= 0} {
	    set smenu .params.body.area.edits.${pname}_sel.menu
	    set sitems [${smenu} index end]
	    for {set idx 0} {$idx <= $sitems} {incr idx} {
		set curcommand [${smenu} entrycget $idx -command]
		${smenu} entryconfigure $idx -command "$curcommand ; \
		magic::update_dialog $callback $pname $gencell_type $library"
	    }
	}
    }
}

#----------------------------------------------------------
# Execute callback procedure, then run bounds checks
#----------------------------------------------------------

proc magic::update_dialog {callback pname gencell_type library} {
    set pdefaults [${library}::${gencell_type}_defaults]
    set parameters [dict merge $pdefaults [magic::gencell_getparams]]

    if {[dict exists $parameters gencell]} {
        # Setting special parameter "gencell" forces the gencell to change type
	set gencell_type [dict get $parameters gencell]
	set pdefaults [${library}::${gencell_type}_defaults]
	set parameters [dict merge $pdefaults [magic::gencell_getparams]]
    }

    if {$callback != {}} {
       set parameters [$callback $pname $parameters]
    }
    if {[catch {set parameters [${library}::${gencell_type}_check $parameters]} \
		checkerr]} {
	puts stderr $checkerr
    }
    magic::gencell_setparams $parameters
}

#----------------------------------------------------------
#  Add a standard checkbox parameter to the gencell window
#----------------------------------------------------------

proc magic::add_checkbox {pname ptext parameters} {

   if [dict exists $parameters $pname] {
        set value [dict get $parameters $pname]
   } else {
       set value ""
   }

   set numrows [lindex [grid size .params.body.area.edits] 1]
   label .params.body.area.edits.${pname}_lab -text $ptext
   checkbutton .params.body.area.edits.${pname}_chk -variable magic::${pname}_val
   grid .params.body.area.edits.${pname}_lab -row $numrows -column 0 -sticky ens
   grid .params.body.area.edits.${pname}_chk -row $numrows -column 1 -sticky wns
   set magic::${pname}_val $value
}

#----------------------------------------------------------
# Add a message box (informational, not editable) to the
# gencell window.  Note that the text does not have to be
# in the parameter list, as it can be upated through the
# textvariable name.
#----------------------------------------------------------

proc magic::add_message {pname ptext parameters {color blue}} {

   if [dict exists $parameters $pname] {
      set value [dict get $parameters $pname]
   } else {
      set value ""
   }

   set numrows [lindex [grid size .params.body.area.edits] 1]
   label .params.body.area.edits.${pname}_lab -text $ptext
   label .params.body.area.edits.${pname}_txt -text $value \
		-foreground $color -textvariable magic::${pname}_val
   grid .params.body.area.edits.${pname}_lab -row $numrows -column 0 -sticky ens
   grid .params.body.area.edits.${pname}_txt -row $numrows -column 1 -sticky wns
}

#----------------------------------------------------------
#  Add a selectable-list parameter to the gencell window
#  (NOTE:  Use magic::add_dependency to add a callback to
#  the selection list choice.)
#----------------------------------------------------------

proc magic::add_selectlist {pname ptext all_values parameters {itext ""}} {

   if [dict exists $parameters $pname] {
        set value [dict get $parameters $pname]
   } else {
       set value $itext
   }

   set numrows [lindex [grid size .params.body.area.edits] 1]
   label .params.body.area.edits.${pname}_lab -text $ptext
   menubutton .params.body.area.edits.${pname}_sel -menu .params.body.area.edits.${pname}_sel.menu \
		-relief groove -text ${value}
   grid .params.body.area.edits.${pname}_lab -row $numrows -column 0 -sticky ens
   grid .params.body.area.edits.${pname}_sel -row $numrows -column 1 -sticky wns
   menu .params.body.area.edits.${pname}_sel.menu -tearoff 0
   foreach item ${all_values} {
	set cmdtxt ".params.body.area.edits.${pname}_sel configure -text $item"
	.params.body.area.edits.${pname}_sel.menu add radio -label $item \
	-variable magic::${pname}_val -value $item \
	-command $cmdtxt
   }
   set magic::${pname}_val $value
}

#----------------------------------------------------------
#  Add a selectable-list parameter to the gencell window
#  Unlike the routine above, it returns the index of the
#  selection, not the selection itself.  This is useful for
#  keying the selection to other parameter value lists.
#----------------------------------------------------------

proc magic::add_selectindex {pname ptext all_values parameters {ival 0}} {

   if [dict exists $parameters $pname] {
        set value [dict get $parameters $pname]
   } else {
       set value $ival
   }

   set numrows [lindex [grid size .params.body.area.edits] 1]
   label .params.body.area.edits.${pname}_lab -text $ptext
   menubutton .params.body.area.edits.${pname}_sel -menu .params.body.area.edits.${pname}_sel.menu \
		-relief groove -text [lindex ${all_values} ${value}]
   grid .params.body.area.edits.${pname}_lab -row $numrows -column 0 -sticky ens
   grid .params.body.area.edits.${pname}_sel -row $numrows -column 1 -sticky wns
   menu .params.body.area.edits.${pname}_sel.menu -tearoff 0
   set idx 0
   foreach item ${all_values} {
       .params.body.area.edits.${pname}_sel.menu add radio -label $item \
	-variable magic::${pname}_val -value $idx \
	-command ".params.body.area.edits.${pname}_sel configure -text $item"
       incr idx
   }
   set magic::${pname}_val $value
}

#-------------------------------------------------------------
# gencell_defaults ---
#
# Set all parameters for a device.  Start by calling the base
# device's default value list to generate a dictionary.  Then
# parse all values passed in 'parameters', overriding any
# defaults with the passed values.
#-------------------------------------------------------------

proc magic::gencell_defaults {gencell_type library parameters} {
    set basedict [${library}::${gencell_type}_defaults]
    set newdict [dict merge $basedict $parameters]
    return $newdict
}

#-------------------------------------------------------------
# Command tag callback on "select".  "select cell" should
# cause the parameter dialog window to update to reflect the
# selected cell.  If a cell is unselected, then revert to the
# default 'Create' window.
#-------------------------------------------------------------

proc magic::gencell_update {{command {}}} {
    if {[info level] <= 1} {
        if {![catch {set state [wm state .params]}]} {
	    if {[wm state .params] == "normal"} {
		if {$command == "cell"} {
		    # If multiple devices are selected, choose the first in
		    # the list returned by "what -list".
		    set instname [lindex [lindex [lindex [what -list] 2] 0] 0]
		    magic::gencell_dialog $instname {} {} {}
		}
	    }
	}
    }
}

#-------------------------------------------------------------
# updateParamsScrollRegion ---
#
# Change the canvas size when the parameter window changes
# size so that the scrollbar works correctly.
#-------------------------------------------------------------

proc updateParamsScrollRegion {} {
    set bbox [.params.body.area bbox all]
    .params.body.area configure -scrollregion $bbox
    .params.body.area configure -width [lindex $bbox 2]
    .params.body.area configure -height [lindex $bbox 3]
}

#-------------------------------------------------------------
# gencell_dialog ---
#
# Create the dialog window for entering device parameters.  The
# general procedure then calls the dialog setup for the specific
# device.
#
# 1) If gname is NULL and gencell_type is set, then we
#    create a new cell of type gencell_type.
# 2) If gname is non-NULL, then we edit the existing
#    cell of type $gname.
# 3) If gname is non-NULL and gencell_type or library
#    is NULL or unspecified, then we derive the gencell_type
#    and library from the existing cell's property strings
#
# The device setup should be built using the API that defines
# these procedures:
#
# magic::add_entry	 Single text entry window
# magic::add_checkbox    Single checkbox
# magic::add_selectlist  Pull-down menu with list of selections
#
#-------------------------------------------------------------

proc magic::gencell_dialog {instname gencell_type library parameters} {
   if {$gencell_type == {}} {
       # Revert to default state for the device that was previously
       # shown in the parameter window.
       if {![catch {set state [wm state .params]}]} {
          if {$instname == {}} {
	     set devstr [.params.title.lab1 cget -text]
	     if {$devstr == "Edit device:"} {
		 set gencell_type [.params.title.lab2 cget -text]
		 set library [.params.title.lab4 cget -text]
	     } else {
	         return
	     }
	  }
       }
   }

   if {$instname != {}} {
      # Remove any array component of the instance name
      set instname [string map {\\ ""} $instname]
      if {[regexp {^(.*)\[[0-9,]+\]$} $instname valid instroot]} {
	 set instname $instroot
      }
      set gname [instance list celldef [subst $instname]]
      set gencell_type [cellname list property $gname gencell]
      if {$library == {}} {
	 set library [cellname list property $gname library]
      }
      if {$parameters == {}} {
	 set parameters [cellname list property $gname parameters]
      }
      if {$gencell_type == {} || $library == {}} {return}

      if {$parameters == {}} {
	 set parameters [${library}::${gencell_type}_defaults]
      }

      # If the default parameters contain "nocell", then set the
      # standard parameters for fixed devices from the instance
      if {[dict exists $parameters nocell]} {
	 select cell $instname
	 set arcount [array -list count]
	 set arpitch [array -list pitch]

	 dict set parameters nx [expr [lindex $arcount 1] - [lindex $arcount 0] + 1]
	 dict set parameters ny [expr [lindex $arcount 3] - [lindex $arcount 2] + 1]
	 dict set parameters pitchx [lindex $arpitch 0]
	 dict set parameters pitchy [lindex $arpitch 1]
      }
      set ttext "Edit device"
      set itext $instname
   } else {
      set parameters [magic::gencell_defaults $gencell_type $library $parameters]
      set gname "(default)"
      set itext "(default)"
      set ttext "New device"
   }

   # Destroy children, not the top-level window, or else window keeps
   # bouncing around every time something is changed.
   if {[catch {toplevel .params}]} {
       .params.title.lab1 configure -text "${ttext}:"
       .params.title.lab2 configure -text "$gencell_type"
       .params.title.lab4 configure -text "$library"
       .params.title.glab configure -foreground blue -text "$gname"
       .params.title.ient delete 0 end
       .params.title.ient insert 0 "$itext"
       foreach child [winfo children .params.body.area.edits] {
	  destroy $child
       }
       foreach child [winfo children .params.buttons] {
	  destroy $child
       }
   } else {
       frame .params.title
       label .params.title.lab1 -text "${ttext}:"
       label .params.title.lab2 -foreground blue -text "$gencell_type"
       label .params.title.lab3 -text "Library:"
       label .params.title.lab4 -foreground blue -text "$library"
       label .params.title.clab -text "Cellname:"
       label .params.title.glab -foreground blue -text "$gname"
       label .params.title.ilab -text "Instance:"
       entry .params.title.ient -foreground brown -background white
       .params.title.ient insert 0 "$itext"
       ttk::separator .params.sep
       frame .params.body
       canvas .params.body.area
       scrollbar .params.body.sb -command {.params.body.area yview}
       frame .params.buttons

       grid .params.title.lab1 -padx 5 -row 0 -column 0
       grid .params.title.lab2 -padx 5 -row 0 -column 1 -sticky w
       grid .params.title.lab3 -padx 5 -row 0 -column 2
       grid .params.title.lab4 -padx 5 -row 0 -column 3 -sticky w

       grid .params.title.clab -padx 5 -row 1 -column 0
       grid .params.title.glab -padx 5 -row 1 -column 1 -sticky w
       grid .params.title.ilab -padx 5 -row 1 -column 2
       grid .params.title.ient -padx 5 -row 1 -column 3 -sticky ew
       grid columnconfigure .params.title 3 -weight 1

       grid .params.body.area -row 0 -column 0 -sticky nsew
       grid .params.body.sb -row 0 -column 1 -sticky ns
       grid columnconfigure .params.body 0 -weight 1
       grid columnconfigure .params.body 1 -weight 0
       grid rowconfigure .params.body 0 -weight 1

       grid .params.title -row 0 -column 0 -sticky nsew
       grid .params.sep -row 1 -column 0 -sticky nsew
       grid .params.body -row 2 -column 0 -sticky nsew
       grid .params.buttons -row 3 -column 0 -sticky nsew

       grid rowconfigure .params 0 -weight 0
       grid rowconfigure .params 1 -weight 0
       grid rowconfigure .params 2 -weight 1
       grid rowconfigure .params 3 -weight 0
       grid columnconfigure .params 0 -weight 1

       frame .params.body.area.edits
       .params.body.area create window 0 0 -anchor nw -window .params.body.area.edits
       .params.body.area config -yscrollcommand {.params.body.sb set}

       # Make sure scrollbar tracks any window size changes
       bind .params <Configure> updateParamsScrollRegion

       # Allow mouse wheel to scroll the window up and down.
       bind .params.body.area <Button-4> {.params.body.area yview scroll -1 units}
       bind .params.body.area <Button-5> {.params.body.area yview scroll +1 units}
   }

   if {$instname == {}} {
	button .params.buttons.apply -text "Create" -command \
		[subst {set inst \[magic::gencell_create \
		$gencell_type $library {}\] ; \
		magic::gencell_dialog \$inst $gencell_type $library {} }]
	button .params.buttons.okay -text "Create and Close" -command \
		[subst {set inst \[magic::gencell_create \
		$gencell_type $library {}\] ; \
		magic::gencell_dialog \$inst $gencell_type $library {} ; \
		destroy .params}]
   } else {
	button .params.buttons.apply -text "Apply" -command \
		"magic::gencell_change $instname $gencell_type $library {}"
	button .params.buttons.okay -text "Okay" -command \
		"magic::gencell_change $instname $gencell_type $library {} ;\
		 destroy .params"
   }
   button .params.buttons.reset -text "Reset" -command \
		"magic::gencell_dialog {} ${gencell_type} ${library} {}"
   button .params.buttons.close -text "Close" -command {destroy .params}

   pack .params.buttons.apply -padx 5 -ipadx 5 -ipady 2 -side left
   pack .params.buttons.okay  -padx 5 -ipadx 5 -ipady 2 -side left
   pack .params.buttons.close -padx 5 -ipadx 5 -ipady 2 -side right
   pack .params.buttons.reset -padx 5 -ipadx 5 -ipady 2 -side right

   # Invoke the callback procedure that creates the parameter entries

   ${library}::${gencell_type}_dialog $parameters

   # Add standard callback to all entry fields to run parameter bounds checks
   magic::add_check_callbacks $gencell_type $library

   # Make sure the window is raised
   raise .params
}

#-------------------------------------------------------------
