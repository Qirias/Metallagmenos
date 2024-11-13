#include "engine.hpp"

int main() {

    Engine engine;
    engine.init();
    engine.run();
    engine.cleanup();

    return 0;
}
