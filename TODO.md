# TODO: Add Option to Add Time Instead of Automatically Date and Time in Add Calendar Screen

## Tasks
- [ ] Add boolean state variable `isAllDay` in _AddActivityScreenState
- [ ] Add Checkbox widget for "All Day" in the Start Date and Time section
- [ ] Modify the InkWell onTap for start date/time: if isAllDay, only show date picker; else show date and time pickers
- [ ] Update the InputDecorator child text to show only date if isAllDay, else date and time
- [ ] Apply similar logic to end date/time if needed (but since optional, perhaps keep as is or add checkbox there too)
- [ ] Update validation: require date always, time only if not allDay
- [ ] In save logic, when creating DateTime, if isAllDay, set hour and minute to 0
- [ ] Test the changes to ensure UI toggles correctly and saves properly
