import SmartHomeCard from "../components/SmartHomeCard"
import { useDevices } from "../hooks/useDevices"
import { Lightbulb } from "lucide-react"
import { Progress } from "@/components/ui/progress"


function Devices() {
  const { devices } = useDevices();
  const activeDevices = devices.filter(device => device.state === "on").length;
  const totalDevices = devices.length
  const progress = totalDevices > 0 ? (activeDevices / totalDevices) * 100 : 0
    
    return (
        <div className="space-y-2">
            
            <h3 className="text-xl font-semibold text-black">Smart Home</h3>

            <p className="text-xs text-[#be185d]">
                {activeDevices} of {totalDevices} active
            </p>

            <Progress value={progress} className="h-1 bg-[#f9ddea] [&_[data-slot=progress-indicator]]:bg-[#db2777]"/>
        
            <div className="grid grid-cols-6 p-4 gap-4">

                {devices.map(device => (
                    <SmartHomeCard
                        key={device.entity_id}
                        icon={Lightbulb}
                        color="#ef6cba"
                        device={device.name}
                        location={device.area ?? "Unassigned"}
                        isOn={device.state === "on"}
                        onToggle={checked => toggleDevice(device.entity_id, checked)}
                    />
                ))}
            </div>
        </div> 
    )
}

export default Devices