import { useState } from "react"
import SmartHomeCard from "../components/SmartHomeCard"
import { Lightbulb, Thermometer, Lock, Mic } from "lucide-react"
import { Progress } from "@/components/ui/progress"

function Devices() {

  const [devices, setDevices] = useState([
    { id: "light.bedroom", location: "Bedroom", isOn: true },
  ])

  async function toggleDevice(id, checked) {
    const action = checked ? "turn_on" : "turn_off";

    const response = await fetch("/api/devices/control", {
      method: "POST",
      headers: {
          "Content-Type": "application/json"
      },
      body: JSON.stringify({
          entity_id: id,
          action: action
      })     
    });

    if (!response.ok) {
      toast.add({
        type: "error",
        description: `Failed to control ${id}`
      });

      throw new Error("Failed to control device");
    };

    setDevices(prevDevices =>
      prevDevices.map(device =>
        device.id === id
          ? { ...device, isOn: checked }
          : device
      )
    );
  }

  const activeDevices = devices.filter(device => device.isOn).length
  const totalDevices = devices.length
  const progress = totalDevices > 0
    ? (activeDevices / totalDevices) * 100
    : 0
    
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
                        icon={Lightbulb}
                        color="#ef6cba"
                        device={device.id}
                        location={device.location}
                        onToggle={checked => toggleDevice(device.id, checked)}
                    />
                ))}

            </div>

        </div> 
    )
}

export default Devices