#include "engine.hpp"

int main() {

    MTLEngine engine;
    engine.init();
    engine.run();
    engine.cleanup();

    return 0;
}
