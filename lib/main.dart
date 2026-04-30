import 'package:flutter/material.dart';

// Punto de entrada de la aplicación
void main() {
  runApp(const MiDespertadorApp());
}

// Widget principal que configura el tema general de la app
class MiDespertadorApp extends StatelessWidget {
  const MiDespertadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Despertador',
      debugShowCheckedModeBanner: false, // Oculta la etiqueta de "Debug"
      theme: ThemeData(
        // Usamos Material 3 (el diseño moderno de Android)
        useMaterial3: true,
        // Definimos un color principal (Morado/Violeta)
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      home: const PantallaAlarmas(),
    );
  }
}

// Pantalla principal (Stateful porque la lista de alarmas cambiará de estado)
class PantallaAlarmas extends StatefulWidget {
  const PantallaAlarmas({super.key});

  @override
  State<PantallaAlarmas> createState() => _PantallaAlarmasState();
}

class _PantallaAlarmasState extends State<PantallaAlarmas> {
  // Una lista simple de datos para simular nuestras alarmas
  List<Map<String, dynamic>> alarmas = [
    {"hora": "02:30", "periodo": "PM", "etiqueta": "Despertar", "activa": true},
    {"hora": "07:30", "periodo": "AM", "etiqueta": "Gimnasio", "activa": false},
    {"hora": "10:00", "periodo": "PM", "etiqueta": "Dormir", "activa": true},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],

      // La barra superior de la aplicación
      appBar: AppBar(
        title: const Text('Mis Alarmas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),

      // El cuerpo principal: una lista que se puede desplazar (scroll)
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: alarmas.length,
        itemBuilder: (context, index) {
          final alarma = alarmas[index];

          return Card(
            elevation: 0,
            color: alarma["activa"] ? Colors.white : Colors.grey[200],
            margin: const EdgeInsets.only(bottom: 12.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                // La hora en grande
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      alarma["hora"],
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w300,
                        color: alarma["activa"] ? Colors.black : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      alarma["periodo"],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: alarma["activa"] ? Colors.black : Colors.grey,
                      ),
                    ),
                  ],
                ),
                // Etiqueta de la alarma abajo
                subtitle: Row(
                  children: [
                    Icon(
                      Icons.notifications,
                      size: 16,
                      color: alarma["activa"] ? Colors.grey[600] : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      alarma["etiqueta"],
                      style: TextStyle(
                        color: alarma["activa"]
                            ? Colors.grey[600]
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
                // El interruptor (Switch) a la derecha
                trailing: Switch(
                  value: alarma["activa"],
                  onChanged: (bool nuevoValor) {
                    setState(() {
                      alarma["activa"] = nuevoValor;
                    });
                  },
                ),
              ),
            ),
          );
        },
      ),

      // El botón flotante en la esquina inferior derecha
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Mostrar un pequeño mensaje al presionar el botón
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Función para agregar alarma próximamente'),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
