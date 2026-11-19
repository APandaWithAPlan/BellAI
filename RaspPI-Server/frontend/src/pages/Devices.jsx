import SmartHomeCard from "../components/SmartHomeCard"
import { useToggleDevice } from "../hooks/useToggleDevice"
import { Lightbulb } from "lucide-react"
import { Progress } from "@/components/ui/progress"


function Devices() {
  const { devices, toggleDevice } = useToggleDevice();
  const lights = Object.values(devices).filter(device => device.entity_id.startsWith("light."));
  const activeDevices = lights.filter(device => device.state === "on").length;
  const totalDevices = lights.length;
  const progress = totalDevices > 0 ? (activeDevices / totalDevices) * 100 : 0;

    return (
        <div className="space-y-2">
            
            <h3 className="text-xl font-semibold text-black">Smart Home</h3>

            <p className="text-xs text-[#be185d]">
                {activeDevices} of {totalDevices} active
            </p>

            <Progress value={progress} className="h-1 bg-[#f9ddea] [&_[data-slot=progress-indicator]]:bg-[#db2777]"/>
        
            <div className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4 p-4">

                {lights.map(light => (
                    <SmartHomeCard
                        key={light.entity_id}
                        icon={Lightbulb}
                        color="#ef6cba"
                        device={light.name ?? "Unknown Device"}
                        location={light.area ?? "Unassigned"}
                        isOn={light.state === "on"}
                        onToggle={checked => toggleDevice(light.entity_id, checked)}
                    />
                ))}
            </div>
        </div> 
    )
}

export default Devices